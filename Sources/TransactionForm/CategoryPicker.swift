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
                ORDER BY weighted_count DESC
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
                        Text(category.displayName)
//                            .bold()

//                        CategoryRow(
//                            category: category,
//                            isSelected: store.selectedCategory?.id == category.id
//                        ) {
//                            send(.categoryTapped(category))
//                        }
                    }
                }
            }

            // All Categories section
            if !store.filteredCategories.isEmpty {
                ForEach(store.data.allCategories.elements, id: \.key) { parent, children in
                    Section {
                        Text(parent.title)
                            .bold()
                        //                            CategoryRow(
                        //                                category: parent,
                        //                                isSelected: store.selectedCategory?.id == parent.id
                        //                            ) {
                        //                                send(.categoryTapped(parent))
                        //                            }

                        ForEach(children) { child in
                            Text(child.title)
                            //                                CategoryRow(
                            //                                    category: child,
                            //                                    isSelected: store.selectedCategory?.id == child.id,
                            //                                    isChild: true
                            //                                ) {
                            //                                    send(.categoryTapped(child))
                            //                                }
                        }
                    }
                }
            }

            if store.filteredCategories.isEmpty && store.filteredFrequentCategories.isEmpty {
                ContentUnavailableView.search
            }
        }
        .searchable(text: $store.searchText, prompt: "Search categories")
        .navigationBarTitleDisplayMode(.inline)
        .task { await send(.task).finish() }
    }
}

private struct CategoryRow: View {
    let category: Category
    let isSelected: Bool
    var isChild: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }

                Text(isChild ? "  \(category.title)" : category.title)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }
        }
    }
}

#Preview {
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
        try $0.defaultDatabase.write { db in
            try db.seedSampleData()
        }
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

