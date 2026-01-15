import ComposableArchitecture
import Currency
import IdentifiedCollections
import IssueReporting
import SQLiteData
import SwiftUI

// MARK: - Virtual Instance (Due Recurring Transaction)

/// Represents a recurring transaction that is due to be posted.
/// This is a non-persisted model used only for display and actions.
struct VirtualInstance: Identifiable, Equatable {
    let id: UUID  // The recurring transaction's ID
    let recurringTransaction: RecurringTransaction
    let dueDate: Date
    let category: Category?
    let tags: [Tag]

    var description: String { recurringTransaction.description }
    var valueMinorUnits: Int { recurringTransaction.valueMinorUnits }
    var currencyCode: String { recurringTransaction.currencyCode }
    var type: Transaction.TransactionType { recurringTransaction.type }
}

@Reducer
struct TransactionsList: Reducer {

    @Reducer
    enum Destination {
        case transactionForm(TransactionFormReducer)
    }

    @ObservableState
    struct State: Equatable {

        @Presents var destination: Destination.State?

        var date: Date

        // Due recurring transactions (virtual instances)
        var dueInstances: [VirtualInstance] = []

        @FetchAll(TransactionsListRow.none) // this query is dynamic
        var rows: [TransactionsListRow]
        var rowsQuery: some Statement<TransactionsListRow> & Sendable {
            @Dependency(\.calendar) var calendar
            let components = calendar.dateComponents([.year, .month], from: date)
            let year = components.year!
            let month = components.month!

            return TransactionsListRow
                .where { $0.transaction.localYear.eq(year) && $0.transaction.localMonth.eq((month)) }
                .select { $0 }
        }

        var rowsByDay: [Int: [TransactionsListRow]] {
            var byDay = Dictionary(grouping: rows) { row in
                row.transaction.localDay
            }
            for (day, dayRows) in byDay {
                byDay[day] = dayRows.sorted { $0.transaction.createdAtUTC > $1.transaction.createdAtUTC }
            }
            return byDay
        }

        var balanceByDay: [Int: Money] {
            var balanceByDay: [Int: Money] = [:]

            for (day, rows) in rowsByDay {
                // Always use converted values (default currency) for totals
                // Skip transactions without conversion (they'll need background processing)
                balanceByDay[day] = rows
                    .compactMap { $0.transaction.signedConvertedMoney }
                    .sum()
            }
            return balanceByDay
        }
        var days: [Int] {
            Array(rowsByDay.keys.sorted().reversed())
        }

        init(date: Date) {
            self.date = date
            self._rows = FetchAll(rowsQuery, animation: .default)
        }
    }

    enum Action: BindableAction, ViewAction {
        enum View {
            case nextMonthButtonTapped
            case onAppear
            case previousMonthButtonTapped
            case deleteTransactions([UUID])
            case transactionTapped(Transaction)
            case dismissTransactionDetailButtonTapped
            case postVirtualInstance(VirtualInstance)
            case skipVirtualInstance(VirtualInstance)
        }

        case binding(BindingAction<State>)
        case view(View)
        case destination(PresentationAction<Destination.Action>)
        case dueInstancesLoaded([VirtualInstance])
    }

    @Dependency(\.calendar) private var calendar
    @Dependency(\.defaultDatabase) private var database

    @Dependency(\.date.now) private var now

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .destination:
                return .none

            case let .dueInstancesLoaded(instances):
                state.dueInstances = instances
                return .none

            case let .view(viewAction):
                switch viewAction {
                case let .deleteTransactions(ids):
                    return .run { _ in
                        await withErrorReporting {
                            try await database.write { db in
                                try Transaction
                                    .where { $0.id.in(ids) }
                                    .delete()
                                    .execute(db)
                            }
                        }
                    }

                case .nextMonthButtonTapped:
                    state.date = calendar.date(byAdding: .month, value: 1, to: state.date)!
                    return loadTransactions(state: state)

                case .onAppear:
                    return .merge(
                        loadTransactions(state: state),
                        loadDueInstances()
                    )

                case .previousMonthButtonTapped:
                    state.date = calendar.date(byAdding: .month, value: -1, to: state.date)!
                    return loadTransactions(state: state)

                case let .transactionTapped(transaction):
                    state.destination = .transactionForm(TransactionFormReducer.State(
                        transaction: Transaction.Draft(transaction),
                        formMode: .editTransaction
                    ))
                    return .none

                case .dismissTransactionDetailButtonTapped:
                    state.destination = nil
                    return .none

                case let .postVirtualInstance(instance):
                    // Open transaction form pre-filled from the virtual instance
                    var draft = Transaction.Draft()
                    draft.description = instance.description
                    draft.valueMinorUnits = instance.valueMinorUnits
                    draft.currencyCode = instance.currencyCode
                    draft.type = instance.type
                    // Set the date to the due date (user can change)
                    let dateComponents = calendar.dateComponents([.year, .month, .day], from: instance.dueDate)
                    draft.localYear = dateComponents.year!
                    draft.localMonth = dateComponents.month!
                    draft.localDay = dateComponents.day!

                    state.destination = .transactionForm(TransactionFormReducer.State(
                        transaction: draft,
                        formMode: .postFromRecurring(instance.recurringTransaction),
                        category: instance.category,
                        tags: instance.tags
                    ))
                    return .none

                case let .skipVirtualInstance(instance):
                    let recurringTransaction = instance.recurringTransaction
                    return .run { send in
                        await withErrorReporting {
                            try await database.write { db in
                                // Calculate the next due date
                                let rule = RecurrenceRule.from(recurringTransaction: recurringTransaction)
                                let nextDueDate = rule.nextOccurrence(after: recurringTransaction.nextDueDate)

                                // Update the recurring transaction
                                try RecurringTransaction
                                    .where { $0.id.eq(recurringTransaction.id) }
                                    .update { $0.nextDueDate = nextDueDate }
                                    .execute(db)
                            }
                        }
                        // Reload due instances
                        await send(.view(.onAppear))
                    }
                }
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }

    private func loadTransactions(state: State) -> Effect<Action> {
        let fetchAll = state.$rows
        let query = state.rowsQuery
        return .run { _ in
            try await fetchAll.load(query, animation: .default)
        }
    }

    private func loadDueInstances() -> Effect<Action> {
        .run { send in
            let instances = try await database.read { db -> [VirtualInstance] in
                // Get all active recurring transactions where nextDueDate <= today
                let recurringTransactions = try RecurringTransaction
                    .where { $0.status.eq(RecurringTransactionStatus.active) && $0.nextDueDate.lte(now) }
                    .order(by: \.nextDueDate)
                    .select { $0 }
                    .fetchAll(db)

                return try recurringTransactions.map { rt in
                    // Load category for this recurring transaction
                    let categoryID = try RecurringTransactionCategory
                        .where { $0.recurringTransactionID.eq(rt.id) }
                        .select { $0.categoryID }
                        .fetchOne(db)

                    let category = try categoryID.flatMap {
                        try Category.find($0).fetchOne(db)
                    }

                    // Load tags for this recurring transaction
                    let tagIDs = try RecurringTransactionTag
                        .where { $0.recurringTransactionID.eq(rt.id) }
                        .select { $0.tagID }
                        .fetchAll(db)
                    let tags = try tagIDs.compactMap {
                        try Tag.find($0).fetchOne(db)
                    }

                    return VirtualInstance(
                        id: rt.id,
                        recurringTransaction: rt,
                        dueDate: rt.nextDueDate,
                        category: category,
                        tags: tags
                    )
                }
            }
            await send(.dueInstancesLoaded(instances))
        }
    }
}
extension TransactionsList.Destination.State: Equatable {}

@ViewAction(for: TransactionsList.self)
struct TransactionsListView: View {

    @Bindable var store: StoreOf<TransactionsList>

    var body: some View {
        NavigationStack {
            List {
                // Due section for virtual instances
                if !store.dueInstances.isEmpty {
                    Section {
                        ForEach(store.dueInstances) { instance in
                            VirtualInstanceRow(
                                instance: instance,
                                onPost: { send(.postVirtualInstance(instance)) },
                                onSkip: { send(.skipVirtualInstance(instance)) }
                            )
                        }
                    } header: {
                        HStack {
                            Label {
                                Text("Due", bundle: .main)
                                    .font(.caption.bold())
                                    .textCase(nil)
                            } icon: {
                                Image(systemName: "clock.badge.exclamationmark")
                            }
                            .foregroundStyle(.orange)

                            Spacer()

                            if store.dueInstances.count > 1 {
                                Text("\(store.dueInstances.count) items", bundle: .main)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Regular transactions by day
                ForEach(store.days, id: \.self) { day in
                    let rows = store.rowsByDay[day] ?? []
                    Section {
                        ForEach(rows) { row in
                            Button {
                                send(.transactionTapped(row.transaction))
                            } label: {
                                TransactionView(
                                    transaction: row.transaction,
                                    category: row.category,
                                    tags: row.tags,
                                    location: row.location
                                )
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            let ids = indexSet.map { rows[$0].transaction.id }
                            send(.deleteTransactions(ids), animation: .default)
                        }
                    } header: {
                        sectionHeaderView(day: day)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    } footer: {
                        if day == store.days.last {
                            Spacer(minLength: 80)
                        }
                    }
                }
            }
            .onAppear { send(.onAppear) }
            .navigationTitle(store.date.formatted(Date.FormatStyle().month(.wide)))
            .listStyle(.grouped)
            .listSectionSeparator(.hidden)
            .listRowSeparator(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        send(.previousMonthButtonTapped, animation: .default)
                    } label: {
                        Image(systemName: "chevron.backward")
                            .renderingMode(.template)
                            .foregroundColor(.accentColor)
                            .padding(8)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        send(.nextMonthButtonTapped, animation: .default)
                    } label: {
                        Image(systemName: "chevron.forward")
                            .renderingMode(.template)
                            .foregroundColor(.accentColor)
                            .padding(8)
                    }
                }
            }
            .sheet(
                item: $store.scope(
                    state: \.destination?.transactionForm,
                    action: \.destination.transactionForm
                )
            ) { transactionFormStore in
                NavigationStack {
                    TransactionFormView(store: transactionFormStore)
                        .navigationTitle(transactionFormStore.navigationTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button {
                                    send(.dismissTransactionDetailButtonTapped)
                                } label: {
                                    Image(systemName: "xmark")
                                }
                            }
                        }
                }
                .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private func sectionHeaderView(day: Int) -> some View {
        if let transaction = store.rowsByDay[day]?.first?.transaction {
            VStack(spacing: 0) {
                HStack {
                    Text(transaction.localDate.formattedRelativeDay())
                        .font(.caption.bold())
                        .textCase(nil)
                    Spacer()
                    if let balance = store.balanceByDay[day] {
                        ValueView(money: balance)
                            .font(.footnote)
                    }
                }
            }
        }
    }
}

// MARK: - Virtual Instance Row

private struct VirtualInstanceRow: View {
    let instance: VirtualInstance
    let onPost: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.description.isEmpty ? "Untitled" : instance.description)
                        .font(.headline)

                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                            .font(.caption2)
                        Text(dueDateText)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text(formattedAmount)
                    .font(.headline)
                    .foregroundStyle(instance.type == .income ? .green : .primary)
            }

            HStack(spacing: 12) {
                Button {
                    onPost()
                } label: {
                    Label("Post", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    onSkip()
                } label: {
                    Label("Skip", systemImage: "forward.fill")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedAmount: String {
        let money = Money(
            value: Int64(instance.valueMinorUnits),
            currencyCode: instance.currencyCode
        )
        let prefix = instance.type == .expense ? "-" : "+"
        return "\(prefix)\(money.amount.description) \(money.currencyCode)"
    }

    private var dueDateText: String {
        @Dependency(\.date.now) var now
        @Dependency(\.calendar) var calendar

        let dueDate = instance.dueDate
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        if calendar.isDate(dueDate, inSameDayAs: now) {
            return String(localized: "Due today", bundle: .main)
        } else if calendar.isDate(dueDate, inSameDayAs: yesterday) {
            return String(localized: "Due yesterday", bundle: .main)
        } else {
            let days = calendar.dateComponents([.day], from: dueDate, to: now).day ?? 0
            if days > 0 {
                return String(localized: "\(days) days overdue", bundle: .main)
            } else {
                return dueDate.formatted(date: .abbreviated, time: .omitted)
            }
        }
    }
}

#Preview {
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
        try seedSampleData()
    }
    TransactionsListView(
        store: Store(initialState: TransactionsList.State(date: .now)) {
            TransactionsList()
                ._printChanges()
        }
    )
    .tint(.purple)
}
