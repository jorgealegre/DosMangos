import Collections
import ComposableArchitecture
import SQLiteData
import SwiftUI

@Reducer
struct CategoryPicker {

    struct CategoriesRequest: FetchKeyRequest, Equatable {
        struct Value: Equatable {
            var allCategories: OrderedDictionary<Category, [Subcategory]> = [:]
            var frequentSubcategories: [Subcategory] = []
        }

        func fetch(_ db: Database) throws -> Value {
            // Fetch all categories with hierarchical grouping using AllCategories view
            let allCategoriesRows = try AllCategories
                .order { ($0.categoryID, $0.subcategoryTitle) }
                .fetchAll(db)

            let allCategories = allCategoriesRows.reduce(into: OrderedDictionary<Category, [Subcategory]>()) { dict, row in
                let category = Category(title: row.categoryID)
                if let subcategoryID = row.subcategoryID, let subcategoryTitle = row.subcategoryTitle {
                    dict[category, default: []].append(
                        Subcategory(id: subcategoryID, title: subcategoryTitle, categoryID: category.id)
                    )
                } else {
                    dict[category, default: []] = dict[category, default: []]
                }
            }

            // Fetch frequent subcategories
            let frequentSubcategories = try #sql(
                """
                SELECT \(Subcategory.columns),
                SUM(CASE
                    WHEN julianday('now') - julianday(transactions.createdAtUTC) <= 30
                    THEN 3
                    ELSE 1
                END) as weighted_count
                FROM subcategories
                JOIN transactionsCategories ON subcategories.id = transactionsCategories.subcategoryID
                JOIN transactions ON transactionsCategories.transactionID = transactions.id
                WHERE julianday('now') - julianday(transactions.createdAtUTC) <= 90
                GROUP BY transactionsCategories.subcategoryID
                ORDER BY weighted_count DESC, subcategories.title
                LIMIT 4
                """,
                as: Subcategory.self
            )
                .fetchAll(db)

            return Value(
                allCategories: allCategories,
                frequentSubcategories: frequentSubcategories
            )
        }
    }

    @ObservableState
    struct State: Equatable {
        @Fetch(CategoriesRequest(), animation: .default)
        var data = CategoriesRequest.Value()

        var searchText: String = ""
        var selectedSubcategory: Subcategory?

        var newCategoryTitle: String = ""
        var newSubcategoryTitles: [Category.ID: String] = [:]

        /// The category ID to focus on for subcategory creation (set after creating a new category)
        var focusedCategoryForNewSubcategory: Category.ID?

        var filteredCategories: OrderedDictionary<Category, [Subcategory]> {
            guard !searchText.isEmpty else {
                return data.allCategories
            }

            let searchLower = searchText.lowercased()
            var filtered: OrderedDictionary<Category, [Subcategory]> = [:]

            for (category, subcategories) in data.allCategories {
                let categoryMatches = category.title.lowercased().contains(searchLower)
                let matchingSubcategories = subcategories.filter { $0.title.lowercased().contains(searchLower) }

                if categoryMatches || !matchingSubcategories.isEmpty {
                    if categoryMatches {
                        // Show category and all matching subcategories
                        filtered[category] = matchingSubcategories.isEmpty ? subcategories : matchingSubcategories
                    } else {
                        // Only show matching subcategories
                        filtered[category] = matchingSubcategories
                    }
                }
            }

            return filtered
        }

        var filteredFrequentSubcategories: [Subcategory] {
            guard !searchText.isEmpty else {
                return data.frequentSubcategories
            }

            let searchLower = searchText.lowercased()
            return data.frequentSubcategories.filter {
                $0.title.lowercased().contains(searchLower)
            }
        }

        init(selectedSubcategory: Subcategory? = nil) {
            self.selectedSubcategory = selectedSubcategory
        }
    }

    enum Action: ViewAction, BindableAction {
        enum Delegate {
            case subcategorySelected(Subcategory)
        }

        enum View {
            case task
            case subcategoryTapped(Subcategory)
            case createCategorySubmitted(title: String)
            case createSubcategorySubmitted(title: String, categoryID: Category.ID)
            case clearFocusedCategory
        }

        case binding(BindingAction<State>)
        case delegate(Delegate)
        case view(View)
        case categoryCreated(Category.ID)
    }

    @Dependency(\.defaultDatabase) private var database

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .delegate:
                return .none

            case let .categoryCreated(categoryID):
                // Focus on the subcategory text field for the newly created category
                state.focusedCategoryForNewSubcategory = categoryID
                state.searchText = ""
                state.newCategoryTitle = ""
                return .none

            case let .view(view):
                switch view {
                case .task:
                    return .none

                case .clearFocusedCategory:
                    state.focusedCategoryForNewSubcategory = nil
                    return .none

                case let .subcategoryTapped(subcategory):
                    return .send(.delegate(.subcategorySelected(subcategory)))

                case let .createCategorySubmitted(title):
                    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return .none }

                    // Create category only, then focus on subcategory field
                    return .run { send in
                        do {
                            try await database.write { db in
                                try Category
                                    .insert { Category.Draft(title: title) }
                                    .execute(db)
                            }
                            await send(.categoryCreated(title))
                        } catch let error as DatabaseError
                                    where error.extendedResultCode == .SQLITE_CONSTRAINT_PRIMARYKEY
                        {
                            reportIssue(error)
                        } catch {
                            reportIssue(error)
                        }
                    }

                case let .createSubcategorySubmitted(title, categoryID):
                    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return .none }

                    return .run { send in
                        do {
                            let subcategory = try await database.write { db in
                                try Subcategory
                                    .insert { Subcategory.Draft(title: title, categoryID: categoryID) }
                                    .returning(\.self)
                                    .fetchOne(db)!
                            }
                            await send(.delegate(.subcategorySelected(subcategory)))
                        } catch {
                            reportIssue(error)
                        }
                    }
                }
            }
        }
    }
}

@ViewAction(for: CategoryPicker.self)
struct CategoryPickerView: View {
    @Bindable var store: StoreOf<CategoryPicker>

    @FocusState private var focusedField: FocusField?

    enum FocusField: Hashable {
        case search
        case newSubcategory(Category.ID)
    }

    var body: some View {
        List {
            // Frequently Used section
            if !store.filteredFrequentSubcategories.isEmpty {
                Section("Frequently Used") {
                    ForEach(store.filteredFrequentSubcategories) { subcategory in
                        Button {
                            send(.subcategoryTapped(subcategory))
                        } label: {
                            let isSelected = store.selectedSubcategory == subcategory
                            Label(
                                "\(subcategory.categoryID) › \(subcategory.title)",
                                systemImage: isSelected ? "checkmark.circle.fill" : "circle"
                            )
                            .foregroundStyle(isSelected ? Color.accentColor : .primary)
                        }
                    }
                }
            }

            // All Categories section
            if !store.filteredCategories.isEmpty {
                Section("All Categories") {
                    newCategoryTextField
                }

                ForEach(store.filteredCategories.elements, id: \.key) { category, subcategories in
                    Section {
                        Text(category.title)
                            .bold()
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(subcategories) { subcategory in
                            Button {
                                send(.subcategoryTapped(subcategory))
                            } label: {
                                let isSelected = store.selectedSubcategory == subcategory
                                Label(subcategory.title, systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                            }
                        }

                        newSubcategoryTextField(category: category)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No Results for \"\(store.searchText)\"", systemImage: "magnifyingglass")
                } description: {
                    Text("Check the spelling, try a new search or create a new category called \"\(store.searchText)\".")
                } actions: {
                    Button {
                        send(.createCategorySubmitted(title: store.searchText))
                    } label: {
                        Text("Create category \(Text("\"\(store.searchText)\"").bold())")
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .listSectionSpacing(.compact)
        .searchable(text: $store.searchText, prompt: "Search categories")
        .searchFocused($focusedField, equals: .search)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .task { await send(.task).finish() }
        .onAppear { focusedField = .search }
        .onChange(of: store.focusedCategoryForNewSubcategory) { _, categoryID in
            if let categoryID {
                focusedField = .newSubcategory(categoryID)
                send(.clearFocusedCategory)
            }
        }
    }

    private var newCategoryTextField: some View {
        TextField("New category", text: $store.newCategoryTitle)
            .bold()
            .submitLabel(.done)
            .autocorrectionDisabled()
            .onSubmit {
                send(.createCategorySubmitted(title: store.newCategoryTitle))
            }
    }

    private func newSubcategoryTextField(category: Category) -> some View {
        TextField(
            "New subcategory for \(category.title)",
            text: Binding(
                get: { store.newSubcategoryTitles[category.id] ?? "" },
                set: { newValue in
                    var dict = store.newSubcategoryTitles
                    dict[category.id] = newValue
                    store.newSubcategoryTitles = dict
                }
            )
        )
        .focused($focusedField, equals: .newSubcategory(category.id))
        .padding(.leading)
        .autocorrectionDisabled()
        .submitLabel(.done)
        .onSubmit {
            send(.createSubcategorySubmitted(
                title: store.newSubcategoryTitles[category.id] ?? "",
                categoryID: category.id
            ))
        }
    }
}

#Preview {
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
        try seedSampleData()
    }

    NavigationStack {
        CategoryPickerView(
            store: Store(initialState: CategoryPicker.State()) {
                CategoryPicker()
                    ._printChanges()
            }
        )
    }
}
