import ComposableArchitecture
import Foundation
import SwiftUI

@Reducer
struct TransactionFormReducer: Reducer {
    @ObservableState
    struct State: Equatable {
        enum Field {
            case value, description
        }

        var isDatePickerVisible: Bool
        var isPresentingCategoriesPopover: Bool
        var isPresentingTagsPopover: Bool
        var focus: Field?
        var transaction: Transaction.Draft
        /// The user-selected calendar day that the transaction "happened on".
        var transactionDate: Date
        var selectedCategories: [Category]
        var selectedTags: [Tag]
        /// UI is currently whole-dollars only (cents ignored), e.g. "12".
        var valueText: String

        init(
            isDatePickerVisible: Bool = false,
            isPresentingCategoriesPopover: Bool = false,
            isPresentingTagsPopover: Bool = false,
            focus: Field? = .value,
            draft: Transaction.Draft? = nil,
            selectedCategories: [Category] = [],
            selectedTags: [Tag] = []
        ) {
            @Dependency(\.date.now) var now
            let nowLocal = now.localDateComponents()
            let defaultTransactionDate =
                Date.localDate(year: nowLocal.year, month: nowLocal.month, day: nowLocal.day) ?? now

            self.isDatePickerVisible = isDatePickerVisible
            self.isPresentingCategoriesPopover = isPresentingCategoriesPopover
            self.isPresentingTagsPopover = isPresentingTagsPopover
            self.focus = focus
            let transaction = draft ?? Transaction.Draft(
                description: "",
                valueMinorUnits: 0,
                currencyCode: "USD",
                type: .expense,
                createdAtUTC: now,
                localYear: nowLocal.year,
                localMonth: nowLocal.month,
                localDay: nowLocal.day
            )
            self.transactionDate = draft
                .flatMap { existing in
                    Date.localDate(year: existing.localYear, month: existing.localMonth, day: existing.localDay)
                } ?? defaultTransactionDate
            self.transaction = transaction
            self.selectedCategories = selectedCategories
            self.selectedTags = selectedTags
            self.valueText = transaction.valueMinorUnits != 0 ? String(transaction.valueMinorUnits / 100) : ""
        }
    }

    enum Action: ViewAction, BindableAction {
        enum Delegate {
        }
        @CasePathable
        enum View {
            case dateButtonTapped
            case categoriesButtonTapped
            case tagsButtonTapped
            case nextDayButtonTapped
            case previousDayButtonTapped
            case saveButtonTapped
            case setDescription(String)
            case valueInputFinished
        }
        case binding(BindingAction<State>)
        case delegate(Delegate)
        case view(View)
        case transactionTypeChanged(Transaction.TransactionType)
    }

    @Dependency(\.calendar) private var calendar
    @Dependency(\.dismiss) private var dismiss
    @Dependency(\.defaultDatabase) private var database

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding(\.valueText):
                state.transaction.valueMinorUnits = Int(state.valueText).map { $0 * 100 } ?? 0
                return .none

            case .binding:
                return .none

            case .delegate:
                return .none

            case let .view(view):
                switch view {
                case .categoriesButtonTapped:
                    state.isPresentingCategoriesPopover.toggle()
                    return .none

                case .tagsButtonTapped:
                    state.isPresentingTagsPopover.toggle()
                    return .none

                case .dateButtonTapped:
                    state.isDatePickerVisible.toggle()
                    return .none

                case .nextDayButtonTapped:
                    state.transactionDate = calendar.date(byAdding: .day, value: 1, to: state.transactionDate)!
                    return .none

                case .previousDayButtonTapped:
                    state.transactionDate = calendar.date(byAdding: .day, value: -1, to: state.transactionDate)!
                    return .none

                case .saveButtonTapped:
                    state.focus = nil
                    var transaction = state.transaction
                    let transactionDate = state.transactionDate
                    let selectedCategories = state.selectedCategories
                    let selectedTags = state.selectedTags
                    // Derive the stable local Y/M/D label at the persistence boundary.
                    let local = transactionDate.localDateComponents()
                    transaction.localYear = local.year
                    transaction.localMonth = local.month
                    transaction.localDay = local.day
                    return .run { [transaction] _ in
                        withErrorReporting {
                            try database.write { db in
                                let transactionID = try Transaction.upsert { transaction }
                                    .returning(\.id)
                                    .fetchOne(db)!
                                try TransactionCategory
                                    .where { $0.transactionID.eq(transactionID) }
                                    .delete()
                                    .execute(db)
                                try TransactionCategory.insert {
                                    selectedCategories.map { category in
                                        TransactionCategory.Draft(transactionID: transactionID, categoryID: category.id)
                                    }
                                }
                                .execute(db)
                                try TransactionTag
                                    .where { $0.transactionID.eq(transactionID) }
                                    .delete()
                                    .execute(db)
                                try TransactionTag.insert {
                                    selectedTags.map { tag in
                                        TransactionTag.Draft(transactionID: transactionID, tagID: tag.id)
                                    }
                                }
                                .execute(db)
                            }
                        }
                        await dismiss()
                    }

                case let .setDescription(description):
                    state.transaction.description = description
                    return .none

                case .valueInputFinished:
                    state.focus = .description
                    state.valueText = String(state.transaction.valueMinorUnits / 100)
                    return .none
                }

            case let .transactionTypeChanged(transactionType):
                state.transaction.type = transactionType
                return .none
            }
        }
    }
}

@ViewAction(for: TransactionFormReducer.self)
struct TransactionFormView: View {

    @FocusState var focus: TransactionFormReducer.State.Field?

    @Bindable var store: StoreOf<TransactionFormReducer>

    var body: some View {
        Form {
            valueInput
            typePicker
            dateTimePicker
            categoriesSection
            tagsSection
            descriptionInput
            saveButton
        }
        .bind($store.focus, to: $focus)
    }

    @ViewBuilder
    private var valueInput: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(store.transaction.currencyCode)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Currency")

            TextField("0", text: $store.valueText)
                .font(.system(size: 80).bold())
                .minimumScaleFactor(0.2)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
                .focused($focus, equals: .value)
                .onSubmit { send(.valueInputFinished) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var typePicker: some View {
        Picker("Type", selection: $store.transaction.type) {
            Text("Expense").tag(Transaction.TransactionType.expense)
            Text("Income").tag(Transaction.TransactionType.income)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var dateTimePicker: some View {
        Section {
            HStack {
                Button {
                    send(.dateButtonTapped, animation: .default)
                } label: {
                    Text(store.transactionDate.formattedRelativeDay())
                }

                Spacer()

                Button {
                    send(.previousDayButtonTapped)
                } label: {
                    Image(systemName: "chevron.backward")
                        .renderingMode(.template)
                        .foregroundColor(.accentColor)
                        .padding(8)
                }
                Button {
                    send(.nextDayButtonTapped)
                } label: {
                    Image(systemName: "chevron.forward")
                        .renderingMode(.template)
                        .foregroundColor(.accentColor)
                        .padding(8)
                }
            }
            .buttonStyle(BorderlessButtonStyle())

            if store.isDatePickerVisible {
                DatePicker(
                    "",
                    selection: $store.transactionDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .transition(.identity)
            }
        }
    }

    @ViewBuilder
    private var descriptionInput: some View {
        Section {
            TextField(
                "Description",
                text: Binding(
                    get: {
                        store.transaction.description
                    },
                    set: { newDescription in
                        if Set(newDescription).subtracting(Set(store.transaction.description)).contains("\n") {
                            // submit happened
                            send(.saveButtonTapped)
                        } else {
                            send(.setDescription(newDescription))
                        }
                    }
                ),
                axis: .vertical
            )
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($focus, equals: .description)
        }
    }

    @ViewBuilder
    private var categoriesSection: some View {
        Section {
            Button {
                send(.categoriesButtonTapped, animation: .default)
            } label: {
                HStack {
                    Image(systemName: "folder.fill")
                        .font(.title)
                        .foregroundStyle(.gray)
                    Text("Categories")
                        .foregroundStyle(Color(.label))
                    Spacer()
                    if let categoriesDetail {
                        categoriesDetail
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .font(.callout)
                            .foregroundStyle(.gray)
                    }
                    Image(systemName: "chevron.right")
                }
            }
        }
        .popover(isPresented: $store.isPresentingCategoriesPopover) {
            NavigationStack {
                CategoriesView(selectedCategories: $store.selectedCategories)
            }
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        Section {
            Button {
                send(.tagsButtonTapped, animation: .default)
            } label: {
                HStack {
                    Image(systemName: "number.square.fill")
                        .font(.title)
                        .foregroundStyle(.gray)
                    Text("Tags")
                        .foregroundStyle(Color(.label))
                    Spacer()
                    if let tagsDetail {
                        tagsDetail
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .font(.callout)
                            .foregroundStyle(.gray)
                    }
                    Image(systemName: "chevron.right")
                }
            }
        }
        .popover(isPresented: $store.isPresentingTagsPopover) {
            NavigationStack {
                TagsView(selectedTags: $store.selectedTags)
            }
        }
    }

    private var categoriesDetail: Text? {
        guard !store.selectedCategories.isEmpty else { return nil }
        let allCategories = store.selectedCategories.map(\.title).joined(separator: ", ")
        return Text(allCategories)
    }

    private var tagsDetail: Text? {
        guard !store.selectedTags.isEmpty else { return nil }
        let allTags = store.selectedTags.map { "#\($0.title)" }.joined(separator: " ")
        return Text(allTags)
    }

    @ViewBuilder
    private var saveButton: some View {
        Section {
            Button("Save") {
                send(.saveButtonTapped)
            }
        }
    }
}

#Preview {
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try appDatabase()
    }
    Color.clear
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            NavigationStack {
                TransactionFormView(
                    store: Store(initialState: TransactionFormReducer.State()) {
                        TransactionFormReducer()
                            ._printChanges()
                    }
                )
                .navigationTitle("New Transaction")
            }
            .tint(.purple)
        }
}
