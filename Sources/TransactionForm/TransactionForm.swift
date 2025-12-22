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

        var isDatePickerVisible: Bool = false
        var isPresentingCategoriesPopover: Bool = false
        var isPresentingTagsPopover: Bool = false
        var focus: Field? = .value
        var transaction: Transaction.Draft
        var selectedCategory: Category?
        var selectedTags: [Tag] = []
        /// UI is currently whole-dollars only (cents ignored), e.g. "12".

        init(transaction: Transaction.Draft) {
            self.transaction = transaction
            // TODO: load the tags and categories for this transaction
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
            case valueInputFinished
        }
        case binding(BindingAction<State>)
        case delegate(Delegate)
        case view(View)
    }

    @Dependency(\.calendar) private var calendar
    @Dependency(\.dismiss) private var dismiss
    @Dependency(\.defaultDatabase) private var database

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
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
                    state.transaction.localDate = calendar
                        .date(byAdding: .day, value: 1, to: state.transaction.localDate)!
                    return .none

                case .previousDayButtonTapped:
                    state.transaction.localDate = calendar
                        .date(byAdding: .day, value: -1, to: state.transaction.localDate)!
                    return .none

                case .saveButtonTapped:
                    state.focus = nil
                    let transaction = state.transaction
                    let selectedCategory = state.selectedCategory
                    let selectedTags = state.selectedTags
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
                                if let category = selectedCategory {
                                    try TransactionCategory.insert {
                                        TransactionCategory.Draft(transactionID: transactionID, categoryID: category.id)
                                    }
                                    .execute(db)
                                }
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

                case .valueInputFinished:
                    state.focus = .description
                    return .none
                }
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

            TextField("0", text: $store.transaction.valueText)
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
                    Text(store.transaction.localDate.formattedRelativeDay())
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
                    selection: $store.transaction.localDate,
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
                text: $store.transaction.description,
                axis: .vertical
            )
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($focus, equals: .description)
            .onSubmit {
                send(.saveButtonTapped)
            }
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
                    if let category = store.selectedCategory {
                        Text(category.title)
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
                CategoriesView(selectedCategories: Binding(
                    get: { store.selectedCategory.map { [$0] } ?? [] },
                    set: { store.selectedCategory = $0.first }
                ))
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
                    store: Store(
                        initialState: TransactionFormReducer.State(
                            transaction: Transaction.Draft()
                        )
                    ) {
                        TransactionFormReducer()
                            ._printChanges()
                    }
                )
                .navigationTitle("New Transaction")
            }
            .tint(.purple)
        }
}
