import ComposableArchitecture
import Currency
import SQLiteData
import SwiftUI

@Reducer
struct GroupDetailReducer: Reducer {

    // MARK: - Balances

    struct BalancesRequest: FetchKeyRequest {
        var groupID: TransactionGroup.ID

        struct Settlement: Equatable, Identifiable {
            var id: String { "\(from.id)-\(to.id)-\(currencyCode)" }
            let from: GroupMember
            let to: GroupMember
            let amount: Int
            let currencyCode: String

            var money: Money {
                Money(value: Int64(amount), currencyCode: currencyCode)
            }
        }

        struct Value: Equatable {
            var settlements: [Settlement] = []
        }

        func fetch(_ db: Database) throws -> Value {
            guard let group = try TransactionGroup.find(groupID).fetchOne(db) else {
                return Value()
            }

            let members = try GroupMember
                .where { $0.groupID.eq(groupID) }
                .fetchAll(db)
            let membersByID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })

            let transactions = try GroupTransaction
                .where { $0.groupID.eq(groupID) }
                .fetchAll(db)

            guard !transactions.isEmpty else { return Value() }

            let transactionsByID = Dictionary(
                uniqueKeysWithValues: transactions.map { ($0.id, $0) }
            )

            let splits = try GroupTransactionSplit
                .where {
                    $0.groupTransactionID.in(
                        GroupTransaction
                            .where { $0.groupID.eq(groupID) }
                            .select(\.id)
                    )
                }
                .fetchAll(db)

            guard !splits.isEmpty else { return Value() }

            let settlements: [Settlement]
            if group.simplifyDebts {
                settlements = Self.simplifiedSettlements(
                    splits: splits,
                    transactionsByID: transactionsByID,
                    membersByID: membersByID
                )
            } else {
                settlements = Self.pairwiseSettlements(
                    splits: splits,
                    transactionsByID: transactionsByID,
                    membersByID: membersByID
                )
            }

            return Value(settlements: settlements)
        }

        // MARK: Simplified debts

        /// Computes net balance per member, then uses greedy matching to minimize
        /// the number of transfers needed to settle all debts.
        private static func simplifiedSettlements(
            splits: [GroupTransactionSplit],
            transactionsByID: [GroupTransaction.ID: GroupTransaction],
            membersByID: [GroupMember.ID: GroupMember]
        ) -> [Settlement] {
            var netByCurrency: [String: [GroupMember.ID: Int]] = [:]

            for split in splits {
                guard let tx = transactionsByID[split.groupTransactionID] else { continue }
                let net = split.paidAmountMinorUnits - split.owedAmountMinorUnits
                netByCurrency[tx.currencyCode, default: [:]][split.memberID, default: 0] += net
            }

            var settlements: [Settlement] = []

            for (currency, balances) in netByCurrency {
                var creditors: [(id: GroupMember.ID, amount: Int)] = []
                var debtors: [(id: GroupMember.ID, amount: Int)] = []

                for (memberID, balance) in balances {
                    if balance > 0 {
                        creditors.append((memberID, balance))
                    } else if balance < 0 {
                        debtors.append((memberID, -balance))
                    }
                }

                creditors.sort { $0.amount > $1.amount }
                debtors.sort { $0.amount > $1.amount }

                var ci = 0, di = 0
                while ci < creditors.count && di < debtors.count {
                    let amount = min(creditors[ci].amount, debtors[di].amount)
                    if amount > 0,
                       let from = membersByID[debtors[di].id],
                       let to = membersByID[creditors[ci].id]
                    {
                        settlements.append(
                            Settlement(
                                from: from, to: to,
                                amount: amount, currencyCode: currency
                            )
                        )
                    }
                    creditors[ci].amount -= amount
                    debtors[di].amount -= amount
                    if creditors[ci].amount == 0 { ci += 1 }
                    if debtors[di].amount == 0 { di += 1 }
                }
            }

            return settlements
        }

        // MARK: Non-simplified (pairwise) debts

        /// Computes per-transaction pairwise debts (each debtor owes each creditor
        /// proportionally), aggregates across transactions, and nets out reverse pairs.
        private static func pairwiseSettlements(
            splits: [GroupTransactionSplit],
            transactionsByID: [GroupTransaction.ID: GroupTransaction],
            membersByID: [GroupMember.ID: GroupMember]
        ) -> [Settlement] {
            struct PairKey: Hashable {
                let currency: String
                let from: GroupMember.ID
                let to: GroupMember.ID
            }

            var pairDebts: [PairKey: Int] = [:]
            let splitsByTransaction = Dictionary(grouping: splits, by: \.groupTransactionID)

            for (txID, txSplits) in splitsByTransaction {
                guard let tx = transactionsByID[txID] else { continue }

                var creditors: [(id: GroupMember.ID, amount: Int)] = []
                var debtors: [(id: GroupMember.ID, amount: Int)] = []

                for split in txSplits {
                    let net = split.paidAmountMinorUnits - split.owedAmountMinorUnits
                    if net > 0 {
                        creditors.append((split.memberID, net))
                    } else if net < 0 {
                        debtors.append((split.memberID, -net))
                    }
                }

                let totalCredit = creditors.reduce(0) { $0 + $1.amount }
                guard totalCredit > 0 else { continue }

                for debtor in debtors {
                    var remaining = debtor.amount
                    for (index, creditor) in creditors.enumerated() {
                        let share: Int
                        if index == creditors.count - 1 {
                            share = remaining
                        } else {
                            share = debtor.amount * creditor.amount / totalCredit
                            remaining -= share
                        }
                        if share > 0 {
                            let key = PairKey(
                                currency: tx.currencyCode,
                                from: debtor.id, to: creditor.id
                            )
                            pairDebts[key, default: 0] += share
                        }
                    }
                }
            }

            // Net out reverse pairs
            struct UnorderedPair: Hashable {
                let a: GroupMember.ID
                let b: GroupMember.ID
                let currency: String
                init(_ m1: GroupMember.ID, _ m2: GroupMember.ID, _ currency: String) {
                    if m1.uuidString < m2.uuidString {
                        a = m1; b = m2
                    } else {
                        a = m2; b = m1
                    }
                    self.currency = currency
                }
            }

            var processed = Set<UnorderedPair>()
            var settlements: [Settlement] = []

            for key in pairDebts.keys {
                let pair = UnorderedPair(key.from, key.to, key.currency)
                guard !processed.contains(pair) else { continue }
                processed.insert(pair)

                let forwardKey = PairKey(currency: key.currency, from: pair.a, to: pair.b)
                let reverseKey = PairKey(currency: key.currency, from: pair.b, to: pair.a)
                let net = pairDebts[forwardKey, default: 0] - pairDebts[reverseKey, default: 0]

                if net > 0, let from = membersByID[pair.a], let to = membersByID[pair.b] {
                    settlements.append(
                        Settlement(from: from, to: to, amount: net, currencyCode: key.currency)
                    )
                } else if net < 0, let from = membersByID[pair.b], let to = membersByID[pair.a] {
                    settlements.append(
                        Settlement(from: from, to: to, amount: -net, currencyCode: key.currency)
                    )
                }
            }

            return settlements
        }
    }

    // MARK: - State

    @ObservableState
    struct State: Equatable {
        let groupID: TransactionGroup.ID
        @Presents var destination: Destination.State?
        @Presents var alert: AlertState<Action.Alert>?

        @FetchOne var group: TransactionGroup?
        @FetchAll var members: [GroupMember]
        @FetchAll var transactions: [GroupTransaction]
        @FetchOne var currentParticipantID: String?
        @Fetch var balances = BalancesRequest.Value()

        init(groupID: TransactionGroup.ID) {
            self.groupID = groupID
            self._group = FetchOne(TransactionGroup.find(groupID))
            self._members = FetchAll(
                GroupMember
                    .where { $0.groupID.eq(groupID) }
                    .order(by: \.name)
            )
            self._transactions = FetchAll(
                GroupTransaction
                    .where { $0.groupID.eq(groupID) }
                    .order { $0.createdAtUTC.desc() }
            )
            self._currentParticipantID = FetchOne(
                LocalSetting
                    .find("currentUserParticipantID")
                    .select(\.value)
            )
            self._balances = Fetch(
                wrappedValue: BalancesRequest.Value(),
                BalancesRequest(groupID: groupID),
                animation: .default
            )
        }
    }

    @Reducer
    enum Destination {
        case addMember(AddMemberReducer)
        case addTransaction(GroupTransactionFormReducer)
    }

    enum Action: ViewAction {
        @CasePathable
        enum Alert {
            case confirmDeleteTapped
            case dismiss
        }

        @CasePathable
        enum Delegate {
            case deleted(TransactionGroup.ID)
        }
        @CasePathable
        enum View {
            case addMemberTapped
            case addTransactionTapped
            case claimMemberTapped(GroupMember.ID)
            case deleteGroupTapped
        }

        case alert(PresentationAction<Alert>)
        case destination(PresentationAction<Destination.Action>)
        case delegate(Delegate)
        case view(View)
        case setError(String)
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.groupClient) var groupClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .alert(.presented(.confirmDeleteTapped)):
                return .run { [groupID = state.groupID] send in
                    do {
                        try await groupClient.deleteGroup(groupID)
                        await send(.delegate(.deleted(groupID)))
                    } catch {
                        await send(.setError(error.localizedDescription))
                    }
                }

            case .alert:
                return .none

            case let .destination(.presented(.addMember(.delegate(.saved(name))))):
                state.destination = nil
                return .run { [groupID = state.groupID] _ in
                    try await database.write { db in
                        try GroupMember.insert {
                            GroupMember.Draft(
                                groupID: groupID,
                                name: name,
                                cloudKitParticipantID: nil
                            )
                        }.execute(db)
                    }
                }

            case .destination(.presented(.addMember(.delegate(.cancelled)))):
                state.destination = nil
                return .none

            case .destination(.presented(.addTransaction(.delegate(.saved)))):
                state.destination = nil
                return .none

            case .destination(.presented(.addTransaction(.delegate(.cancelled)))):
                state.destination = nil
                return .none

            case .destination:
                return .none

            case .delegate:
                return .none

            case let .setError(message):
                state.alert = AlertState {
                    TextState("Action failed")
                } actions: {
                    ButtonState(action: .dismiss) {
                        TextState("OK")
                    }
                } message: {
                    TextState(message)
                }
                return .none

            case let .view(view):
                switch view {
                case .addMemberTapped:
                    state.destination = .addMember(AddMemberReducer.State())
                    return .none

                case .addTransactionTapped:
                    state.destination = .addTransaction(
                        GroupTransactionFormReducer.State(
                            groupID: state.groupID,
                            members: state.members,
                            defaultCurrencyCode: state.group?.defaultCurrencyCode ?? "USD"
                        )
                    )
                    return .none

                case let .claimMemberTapped(memberID):
                    if let currentParticipantID = state.currentParticipantID,
                       state.members.contains(where: { $0.cloudKitParticipantID == currentParticipantID }) {
                        return .send(.setError("You are already linked to a member in this group."))
                    }
                    return .run { send in
                        do {
                            let didClaim = try await groupClient.claimMember(memberID)
                            if !didClaim {
                                await send(.setError("Could not claim this member. You may already be linked to another member in this group, or someone else claimed this one."))
                            }
                        } catch {
                            await send(.setError(error.localizedDescription))
                        }
                    }

                case .deleteGroupTapped:
                    state.alert = AlertState {
                        TextState("Delete group?")
                    } actions: {
                        ButtonState(role: .destructive, action: .confirmDeleteTapped) {
                            TextState("Delete")
                        }
                        ButtonState(role: .cancel, action: .dismiss) {
                            TextState("Cancel")
                        }
                    } message: {
                        TextState("This will remove the group and all group transactions for everyone in the shared group.")
                    }
                    return .none
                }
            }
        }
        .ifLet(\.$destination, action: \.destination)
        .ifLet(\.$alert, action: \.alert)
    }
}

extension GroupDetailReducer.State {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.groupID == rhs.groupID
            && lhs.group == rhs.group
            && lhs.members == rhs.members
            && lhs.transactions == rhs.transactions
            && lhs.currentParticipantID == rhs.currentParticipantID
            && lhs.balances == rhs.balances
    }
}

@ViewAction(for: GroupDetailReducer.self)
struct GroupDetailView: View {
    @Bindable var store: StoreOf<GroupDetailReducer>

    @Dependency(\.groupClient) var groupClient
    @State private var shareError: String?
    @State private var sharedRecord: SharedRecord?

    var body: some View {
        let canClaimAnotherMember = {
            guard let currentParticipantID = store.currentParticipantID else { return false }
            return !store.members.contains(where: { $0.cloudKitParticipantID == currentParticipantID })
        }()

        List {
            if let group = store.group {
                Section("Group") {
                    if !group.description.isEmpty {
                        Text(group.description)
                            .foregroundStyle(.secondary)
                    }
                    Label("Default currency: \(group.defaultCurrencyCode)", systemImage: "dollarsign.circle")
                    Label(group.simplifyDebts ? "Debt simplification: On" : "Debt simplification: Off", systemImage: "arrow.triangle.branch")
                }
            }

            Section("Balances") {
                if store.balances.settlements.isEmpty {
                    Label("All settled up!", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.balances.settlements) { settlement in
                        HStack {
                            Text("\(settlement.from.name) owes \(settlement.to.name)")
                            Spacer()
                            Text(settlement.money.formatted(.full))
                                .fontWeight(.medium)
                        }
                    }
                }
            }

            Section("Members") {
                ForEach(store.members) { member in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name)
                            if member.cloudKitParticipantID == store.currentParticipantID {
                                Text("You")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if member.cloudKitParticipantID == nil {
                                Text("Unclaimed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if member.cloudKitParticipantID == nil, canClaimAnotherMember {
                            Button("Claim") {
                                send(.claimMemberTapped(member.id))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Button {
                    send(.addMemberTapped)
                } label: {
                    Label("Add member", systemImage: "person.badge.plus")
                }
            }

            Section("Transactions") {
                if store.transactions.isEmpty {
                    Text("No transactions yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.transactions) { transaction in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(transaction.description.isEmpty ? "Untitled" : transaction.description)
                                .font(.headline)

                            HStack {
                                Text(transaction.money.formatted(.full))
                                    .font(.subheadline)
                                Spacer()
                                Text(transaction.type == .expense ? "Expense" : "Transfer")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(store.group?.name ?? "Group")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    send(.addTransactionTapped)
                } label: {
                    Image(systemName: "plus")
                }

                Button {
                    Task {
                        do {
                            sharedRecord = try await groupClient.shareGroup(store.groupID)
                        } catch {
                            shareError = error.localizedDescription
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    send(.deleteGroupTapped)
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .sheet(item: $sharedRecord) { sharedRecord in
            CloudSharingView(sharedRecord: sharedRecord)
        }
        .alert("Sharing error", isPresented: Binding(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
        .sheet(
            item: $store.scope(
                state: \.destination?.addMember,
                action: \.destination.addMember
            )
        ) { memberStore in
            NavigationStack {
                AddMemberView(store: memberStore)
            }
        }
        .sheet(
            item: $store.scope(
                state: \.destination?.addTransaction,
                action: \.destination.addTransaction
            )
        ) { txStore in
            NavigationStack {
                GroupTransactionFormView(store: txStore)
            }
        }
        .alert($store.scope(state: \.alert, action: \.alert))
    }
}

#Preview {
    let groupID = try! prepareDependencies {
        try $0.bootstrapDatabase()
        try seedSampleData()

        @Dependency(\.defaultDatabase) var database
        @Dependency(\.uuid) var uuid

        let groupID = uuid()

        try database.write { db in
        }
//        try database.write { db in
//            try TransactionGroup.insert {
//                TransactionGroup.Draft(
//                    id: groupID,
//                    name: "Trip to Paris",
//                    description: "Summer vacation expenses",
//                    defaultCurrencyCode: "EUR",
//                    simplifyDebts: true,
//                    createdAtUTC: Date()
//                )
//            }.execute(db)
//
//            try GroupMember.insert {
//                GroupMember.Draft(groupID: groupID, name: "Alice", cloudKitParticipantID: nil)
//            }.execute(db)
//            try GroupMember.insert {
//                GroupMember.Draft(groupID: groupID, name: "Bob", cloudKitParticipantID: nil)
//            }.execute(db)
//        }
        return groupID
    }

    NavigationStack {
        GroupDetailView(
            store: Store(initialState: GroupDetailReducer.State(groupID: groupID)) {
                GroupDetailReducer()
            }
        )
    }
}
