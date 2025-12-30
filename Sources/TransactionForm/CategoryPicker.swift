import Collections
import ComposableArchitecture
import SQLiteData
import SwiftUI

@Reducer
struct CategoryPicker {

    struct CategoriesRequest: FetchKeyRequest, Equatable {
        struct Value: Equatable {
            var allCategories: OrderedDictionary<Category, [Category]> = [:]
            var frequentCategories: [Category] = []
        }

        func fetch(_ db: Database) throws -> Value {
            // Fetch all categories with hierarchical grouping
            let categories = try Category
                .order {
                    (
                        $0.parentCategoryID ?? $0.title,
                        $0.parentCategoryID.isNot(nil),
                        $0.title
                    )
                }
                .fetchAll(db)

            var allCategories: OrderedDictionary<Category, [Category]> = [:]
            var parent: Category?
            for category in categories {
                if category.parentCategoryID == nil {
                    parent = category
                    allCategories[category] = []
                } else if let parent {
                    allCategories[parent]?.append(category)
                }
            }

            let frequentCategories = try #sql(
                """
                SELECT \(Category.columns),
                SUM(CASE
                    WHEN julianday('now') - julianday(transactions.createdAtUTC) <= 30
                    THEN 3
                    ELSE 1
                END) as weighted_count
                FROM categories
                JOIN transactionsCategories ON categories.title = transactionsCategories.categoryID
                JOIN transactions ON transactionsCategories.transactionID = transactions.id
                WHERE julianday('now') - julianday(transactions.createdAtUTC) <= 90
                GROUP BY transactionsCategories.categoryID
                ORDER BY weighted_count DESC, categories.title
                LIMIT 4
                """,
                as: Category.self
            )
                .fetchAll(db)

            return Value(
                allCategories: allCategories,
                frequentCategories: frequentCategories
            )
        }
    }

    @ObservableState
    struct State: Equatable {
        @Fetch(CategoriesRequest(), animation: .default)
        var data = CategoriesRequest.Value()

        var searchText: String = ""
        var selectedCategory: Category?

        var filteredCategories: OrderedDictionary<Category, [Category]> {
            guard !searchText.isEmpty else {
                return data.allCategories
            }

            let searchLower = searchText.lowercased()
            var filtered: OrderedDictionary<Category, [Category]> = [:]

            for (parent, children) in data.allCategories {
                let parentMatches = parent.title.lowercased().contains(searchLower)
                let matchingChildren = children.filter { $0.title.lowercased().contains(searchLower) }

                if parentMatches || !matchingChildren.isEmpty {
                    if parentMatches {
                        filtered[parent] = children.filter { $0.title.lowercased().contains(searchLower) }
                    } else {
                        filtered[parent] = matchingChildren
                    }
                }
            }

            return filtered
        }

        var filteredFrequentCategories: [Category] {
            guard !searchText.isEmpty else {
                return data.frequentCategories
            }

            let searchLower = searchText.lowercased()
            return data.frequentCategories.filter {
                $0.title.lowercased().contains(searchLower)
            }
        }

        init(selectedCategory: Category? = nil) {
            self.selectedCategory = selectedCategory
        }
    }

    enum Action: ViewAction, BindableAction {
        enum Delegate {
            case categorySelected(Category)
        }

        enum View {
            case task
            case categoryTapped(Category)
        }

        case binding(BindingAction<State>)
        case delegate(Delegate)
        case view(View)
    }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .delegate:
                return .none

            case let .view(view):
                switch view {
                case .task:
                    return .none

                case let .categoryTapped(category):
                    print("jorge; tapped: \(category.displayName)")
                    return .send(.delegate(.categorySelected(category)))
                }
            }
        }
    }
}

@ViewAction(for: CategoryPicker.self)
struct CategoryPickerView: View {
    @Bindable var store: StoreOf<CategoryPicker>

    var body: some View {
        List {
            // Frequently Used section
            if !store.filteredFrequentCategories.isEmpty {
                Section("Frequently Used") {
                    ForEach(store.filteredFrequentCategories) { category in
                        Button {
                            send(.categoryTapped(category))
                        } label: {
                            Label(category.displayName, systemImage: store.selectedCategory == category ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(store.selectedCategory == category ? Color.accentColor : .primary)
                        }
                    }
                }
            }

            // All Categories section
            if !store.filteredCategories.isEmpty {
                ForEach(store.filteredCategories.elements.enumerated(), id: \.1.key) { index, element in
                    let parent = element.key
                    let children = element.value
                    Section(index == 0 ? "All Categories" : "") {
                        Button {
                            send(.categoryTapped(parent))
                        } label: {
                            Label(parent.title, systemImage: store.selectedCategory == parent ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(store.selectedCategory == parent ? Color.accentColor : .primary)
                                .bold()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(children) { child in
                            Button {
                                send(.categoryTapped(child))
                            } label: {
                                Label("\t" + child.title, systemImage: store.selectedCategory == child ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(store.selectedCategory == child ? Color.accentColor : .primary)
                            }
                        }
                    }
                }

            }

            if store.filteredCategories.isEmpty && store.filteredFrequentCategories.isEmpty {
                ContentUnavailableView.search
            }
        }
        .searchable(text: $store.searchText, prompt: "Search categories")
        .searchFocused($isSearchBarFocused)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .task { await send(.task).finish() }
        .onAppear { isSearchBarFocused = true }
    }

    @FocusState var isSearchBarFocused: Bool
}

#Preview {
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
        try seedSampleData()
    }

    NavigationStack {
        CategoryPickerView(
            store: Store(initialState: CategoryPicker.State(selectedCategory: Category(title: "Salary", parentCategoryID: nil))) {
                CategoryPicker()
                    ._printChanges()
            }
        )
    }
}

