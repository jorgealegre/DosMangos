import Collections
import ComposableArchitecture
import SQLiteData
import SwiftUI

@Reducer
struct CategoryListReducer: Reducer {

    struct CategoryRequest: FetchKeyRequest, Equatable {
        struct Value: Equatable {
            let categories: OrderedDictionary<Category, [Category]>
        }

        func fetch(_ db: Database) throws -> Value {
            let categories = try Category
                .order {
                    (
                        $0.parentCategoryID ?? $0.title,
                        $0.parentCategoryID.isNot(nil),
                        $0.title
                    )
                }
                .fetchAll(db)

            var result: OrderedDictionary<Category, [Category]> = [:]
            var parent: Category?
            for category in categories {
                if category.parentCategoryID == nil {
                    parent = category
                    result[category] = []
                } else if let parent {
                    result[parent]?.append(category)
                }
            }
            return Value(categories: result)
        }
    }

    @ObservableState
    struct State: Equatable {
        @Fetch(CategoryRequest())
        var categories = CategoryRequest.Value(categories: [:])


        init() {
        }
    }

    enum Action: ViewAction {
        enum View {
            case task
        }
        case view(View)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .view(view):
                switch view {
                case .task:
                    return .none
                }
            }
        }
    }
}

@ViewAction(for: CategoryListReducer.self)
struct CategoryListView: View {
    let store: StoreOf<CategoryListReducer>

    var body: some View {

//        if true {
//            ContentUnavailableView {
//                Label("No categories", systemImage: "folder.fill")
//            } description: {
//                Text("Create a new category to start grouping your transactions.")
//            } actions: {
//                Button("Create new") {
//
//                }
//            }
//        }

        List {
            TextField("New category", text: .constant(""))
                .padding(.leading)

            ForEach(store.categories.categories.elements, id: \.key) { parent, children in
                Section {
                    Text(parent.title)
                        .bold()
                    ForEach(children) { child in
                        Text("• " + child.title)
                            .padding(.leading)
                    }
                    TextField("New subcategory for \(parent.title)", text: .constant(""))
                        .padding(.leading)
                }
            }
        }
        .navigationTitle("Categories")
        .task { await send(.task).finish() }
    }
}

#Preview {
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
    }
    NavigationStack {
        CategoryListView(
            store: Store(initialState: CategoryListReducer.State()) {
                CategoryListReducer()
                    ._printChanges()
            }
        )
    }
}

