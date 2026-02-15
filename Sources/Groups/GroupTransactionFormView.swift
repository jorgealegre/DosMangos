import ComposableArchitecture
import Currency
import SQLiteData
import SwiftUI

@Reducer
struct GroupTransactionFormReducer: Reducer {
    @ObservableState
    struct State: Equatable {
        @Presents var alert: AlertState<Action.Alert>?
        let groupID: TransactionGroup.ID
        let members: [GroupMember]

        var description = ""
        var amountText = ""
        var currencyCode: String
        var type: GroupTransactionType = .expense
        var splitType: GroupSplitType = .equal
        var selectedMemberIDs: Set<GroupMember.ID>
        var percentageByMember: [GroupMember.ID: String] = [:]
        var fixedByMember: [GroupMember.ID: String] = [:]
        var paidByMember: [GroupMember.ID: String] = [:]

        var includeLocation = false
        var latitudeText = ""
        var longitudeText = ""
        var city = ""
        var countryCode = ""

        let currencyCodes: [String] = CurrencyRegistry.all.keys.sorted()

        init(
            groupID: TransactionGroup.ID,
            members: [GroupMember],
            defaultCurrencyCode: String
        ) {
            self.groupID = groupID
            self.members = members
            self.currencyCode = defaultCurrencyCode
            self.selectedMemberIDs = Set(members.map(\.id))
        }
    }

    enum Action: BindableAction, ViewAction {
        @CasePathable
        enum Alert {
            case dismiss
        }
        @CasePathable
        enum Delegate {
            case saved
            case cancelled
        }
        @CasePathable
        enum View {
            case cancelTapped
            case saveTapped
            case memberToggled(GroupMember.ID, Bool)
        }
        case alert(PresentationAction<Alert>)
        case binding(BindingAction<State>)
        case delegate(Delegate)
        case view(View)
        case setError(String)
    }

    @Dependency(\.groupClient) var groupClient
    @Dependency(\.date.now) var now

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .alert:
                return .none
            case .binding:
                return .none
            case .delegate:
                return .none

            case let .setError(message):
                state.alert = AlertState {
                    TextState("Could not save transaction")
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
                case .cancelTapped:
                    return .send(.delegate(.cancelled))

                case let .memberToggled(memberID, isOn):
                    if isOn {
                        state.selectedMemberIDs.insert(memberID)
                    } else {
                        state.selectedMemberIDs.remove(memberID)
                    }
                    return .none

                case .saveTapped:
                    return .run { [state] send in
                        do {
                            guard !state.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                throw GroupTransactionValidationError.noSplits
                            }

                            guard let totalMinorUnits = Self.parseMinorUnits(state.amountText, currencyCode: state.currencyCode) else {
                                throw GroupTransactionValidationError.owedTotalMismatch
                            }

                            let selectedIDs = state.members
                                .map(\.id)
                                .filter { state.selectedMemberIDs.contains($0) }
                            guard !selectedIDs.isEmpty else {
                                throw GroupTransactionValidationError.noSplits
                            }

                            let owedByMember = try Self.computeOwedMinorUnits(
                                selectedMemberIDs: selectedIDs,
                                splitType: state.splitType,
                                totalMinorUnits: totalMinorUnits,
                                percentageByMember: state.percentageByMember,
                                fixedByMember: state.fixedByMember,
                                currencyCode: state.currencyCode
                            )

                            let paidByMember = try Self.computePaidMinorUnits(
                                selectedMemberIDs: selectedIDs,
                                paidByMember: state.paidByMember,
                                currencyCode: state.currencyCode
                            )

                            let splits = selectedIDs.map { memberID in
                                GroupTransactionSplitInput(
                                    memberID: memberID,
                                    paidAmountMinorUnits: paidByMember[memberID] ?? 0,
                                    owedAmountMinorUnits: owedByMember[memberID] ?? 0,
                                    owedPercentage: state.splitType == .percentage
                                        ? Double(state.percentageByMember[memberID] ?? "")
                                        : nil
                                )
                            }

                            let location: GroupLocationInput?
                            if state.includeLocation,
                               let latitude = Double(state.latitudeText),
                               let longitude = Double(state.longitudeText) {
                                location = GroupLocationInput(
                                    latitude: latitude,
                                    longitude: longitude,
                                    city: state.city.isEmpty ? nil : state.city,
                                    countryCode: state.countryCode.isEmpty ? nil : state.countryCode.uppercased()
                                )
                            } else {
                                location = nil
                            }

                            let input = GroupTransactionInput(
                                groupID: state.groupID,
                                description: state.description,
                                valueMinorUnits: totalMinorUnits,
                                currencyCode: state.currencyCode,
                                type: state.type,
                                splitType: state.splitType,
                                date: now,
                                splits: splits,
                                location: location
                            )

                            _ = try await groupClient.createGroupTransaction(input)
                            await send(.delegate(.saved))
                        } catch {
                            await send(.setError(error.localizedDescription))
                        }
                    }
                }
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}

private extension GroupTransactionFormReducer {
    static func parseMinorUnits(_ text: String, currencyCode: String) -> Int? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let decimal = Decimal(string: normalized) else { return nil }
        if decimal < 0 { return nil }

        let currency = CurrencyRegistry.currency(for: currencyCode)
        let factor = pow(10.0, Double(currency.minorUnits))
        let number = NSDecimalNumber(decimal: decimal)
            .multiplying(by: NSDecimalNumber(value: factor))
        return number.intValue
    }

    static func computeOwedMinorUnits(
        selectedMemberIDs: [GroupMember.ID],
        splitType: GroupSplitType,
        totalMinorUnits: Int,
        percentageByMember: [GroupMember.ID: String],
        fixedByMember: [GroupMember.ID: String],
        currencyCode: String
    ) throws -> [GroupMember.ID: Int] {
        switch splitType {
        case .equal:
            let count = selectedMemberIDs.count
            let base = totalMinorUnits / count
            let remainder = totalMinorUnits - (base * count)
            var result: [GroupMember.ID: Int] = [:]
            for (index, memberID) in selectedMemberIDs.enumerated() {
                result[memberID] = base + (index == 0 ? remainder : 0)
            }
            return result

        case .percentage:
            var result: [GroupMember.ID: Int] = [:]
            var runningTotal = 0
            for memberID in selectedMemberIDs {
                let pct = Double(percentageByMember[memberID] ?? "") ?? 0
                let value = Int((Double(totalMinorUnits) * pct / 100.0).rounded())
                result[memberID] = value
                runningTotal += value
            }
            if let first = selectedMemberIDs.first {
                result[first, default: 0] += totalMinorUnits - runningTotal
            }
            return result

        case .fixed:
            var result: [GroupMember.ID: Int] = [:]
            for memberID in selectedMemberIDs {
                let value = parseMinorUnits(fixedByMember[memberID] ?? "", currencyCode: currencyCode) ?? 0
                result[memberID] = value
            }
            return result
        }
    }

    static func computePaidMinorUnits(
        selectedMemberIDs: [GroupMember.ID],
        paidByMember: [GroupMember.ID: String],
        currencyCode: String
    ) throws -> [GroupMember.ID: Int] {
        var result: [GroupMember.ID: Int] = [:]
        for memberID in selectedMemberIDs {
            let value = parseMinorUnits(paidByMember[memberID] ?? "", currencyCode: currencyCode) ?? 0
            result[memberID] = value
        }
        return result
    }
}

@ViewAction(for: GroupTransactionFormReducer.self)
struct GroupTransactionFormView: View {
    @Bindable var store: StoreOf<GroupTransactionFormReducer>

    var body: some View {
        Form {
            Section("Details") {
                TextField("Description", text: $store.description)
                TextField("Amount", text: $store.amountText)
                    .keyboardType(.decimalPad)
                Picker("Currency", selection: $store.currencyCode) {
                    ForEach(store.currencyCodes, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                Picker("Type", selection: $store.type) {
                    Text("Expense").tag(GroupTransactionType.expense)
                    Text("Transfer").tag(GroupTransactionType.transfer)
                }
                .pickerStyle(.segmented)
            }

            Section("Members involved") {
                ForEach(store.members) { member in
                    Toggle(
                        isOn: Binding(
                            get: { store.selectedMemberIDs.contains(member.id) },
                            set: { send(.memberToggled(member.id, $0)) }
                        )
                    ) {
                        Text(member.name)
                    }
                }
            }

            if store.type == .expense {
                Section("Split mode") {
                    Picker("Split", selection: $store.splitType) {
                        Text("Equal").tag(GroupSplitType.equal)
                        Text("Percentage").tag(GroupSplitType.percentage)
                        Text("Fixed").tag(GroupSplitType.fixed)
                    }
                    .pickerStyle(.segmented)
                }
            }

            if store.splitType == .percentage && store.type == .expense {
                Section("Percentages") {
                    ForEach(store.members.filter { store.selectedMemberIDs.contains($0.id) }) { member in
                        TextField(
                            "\(member.name) %",
                            text: Binding(
                                get: { store.percentageByMember[member.id] ?? "" },
                                set: { store.percentageByMember[member.id] = $0 }
                            )
                        )
                        .keyboardType(.decimalPad)
                    }
                }
            } else if store.splitType == .fixed && store.type == .expense {
                Section("Fixed amounts") {
                    ForEach(store.members.filter { store.selectedMemberIDs.contains($0.id) }) { member in
                        TextField(
                            "\(member.name) amount",
                            text: Binding(
                                get: { store.fixedByMember[member.id] ?? "" },
                                set: { store.fixedByMember[member.id] = $0 }
                            )
                        )
                        .keyboardType(.decimalPad)
                    }
                }
            }

            Section("Who paid") {
                ForEach(store.members.filter { store.selectedMemberIDs.contains($0.id) }) { member in
                    TextField(
                        "\(member.name) paid",
                        text: Binding(
                            get: { store.paidByMember[member.id] ?? "" },
                            set: { store.paidByMember[member.id] = $0 }
                        )
                    )
                    .keyboardType(.decimalPad)
                }
            }

            Section {
                Toggle("Include location", isOn: $store.includeLocation)
                if store.includeLocation {
                    TextField("Latitude", text: $store.latitudeText)
                        .keyboardType(.decimalPad)
                    TextField("Longitude", text: $store.longitudeText)
                        .keyboardType(.decimalPad)
                    TextField("City", text: $store.city)
                    TextField("Country code (ISO)", text: $store.countryCode)
                        .textInputAutocapitalization(.characters)
                }
            } header: {
                Text("Location")
            }
        }
        .navigationTitle("New Group Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { send(.cancelTapped) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { send(.saveTapped) }
                    .disabled(store.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert($store.scope(state: \.alert, action: \.alert))
    }
}

#Preview {
    let members: [GroupMember] = [
        GroupMember(id: UUID(), groupID: UUID(), name: "Alice", cloudKitParticipantID: nil),
        GroupMember(id: UUID(), groupID: UUID(), name: "Bob", cloudKitParticipantID: nil),
        GroupMember(id: UUID(), groupID: UUID(), name: "Charlie", cloudKitParticipantID: nil),
    ]
    NavigationStack {
        GroupTransactionFormView(
            store: Store(
                initialState: GroupTransactionFormReducer.State(
                    groupID: UUID(),
                    members: members,
                    defaultCurrencyCode: "USD"
                )
            ) {
                GroupTransactionFormReducer()
            }
        )
    }
}
