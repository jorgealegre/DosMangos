import Collections
import ComposableArchitecture
import SQLiteData
import SwiftUI

@Reducer
struct CategoriesReducer: Reducer {

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
        @Fetch(CategoryRequest(), animation: .default)
        var categories = CategoryRequest.Value(categories: [:])


        init() {
        }
    }

    enum Action: ViewAction {
        enum View {
            case task
            case createCategory(title: String)
            case createSubcategory(title: String, parentCategoryID: String)
            case deleteCategory(id: String)
        }
        case view(View)
    }

    @Dependency(\.defaultDatabase) private var database

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .view(view):
                switch view {
                case .task:
                    return .none

                case let .createCategory(title):
                    // TODO: I might want to keep the text field filled in and show an error message if there's a unique constraint error for example
                    return .run { _ in
                        do {
                            try database.write { db in
                                try Category.insert {
                                    Category.Draft(title: title)
                                }
                                .execute(db)
                            }
                        } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_PRIMARYKEY {
                            reportIssue(error)
                            // TODO: alert the user
                        } catch {
                            reportIssue(error)
                        }
                    }

                case let .createSubcategory(title, parentCategoryID):
                    // TODO: I might want to keep the text field filled in and show an error message if there's a unique constraint error for example
                    return .run { _ in
                        do {
                            try database.write { db in
                                try Category.insert {
                                    Category.Draft(title: title, parentCategoryID: parentCategoryID)
                                }
                                .execute(db)
                            }
                        } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_PRIMARYKEY {
                            reportIssue(error)
                            // TODO: alert the user
                        } catch {
                            reportIssue(error)
                        }
                    }

                case let .deleteCategory(id):
                    return .run { _ in
                        withErrorReporting {
                            try database.write { db in
                                try Category.find(id)
                                    .delete()
                                    .execute(db)
                            }
                        }
                    }
                }
            }
        }
    }
}

@ViewAction(for: CategoriesReducer.self)
struct CategoriesView: View {
    let store: StoreOf<CategoriesReducer>
    @State private var newCategoryTitle = ""
    @State private var newSubcategoryTitles: [String: String] = [:]

    var body: some View {
        List {
            if store.categories.categories.isEmpty {
                ContentUnavailableView {
                    Label("No categories", systemImage: "folder.fill")
                } description: {
                    Text("Create a new category to start grouping your transactions.")
                }

                newCategoryTextField
            } else {
                newCategoryTextField

                ForEach(store.categories.categories.elements, id: \.key) { parent, children in
                    Section {
                        Text(parent.title)
                            .bold()
                            .swipeActions {
                                Button(role: .destructive) {
                                    send(.deleteCategory(id: parent.id))
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        ForEach(children) { child in
                            Text("• " + child.title)
                                .padding(.leading)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        send(.deleteCategory(id: child.id))
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                        TextField("New subcategory for \(parent.title)", text: Binding(
                            get: { newSubcategoryTitles[parent.id] ?? "" },
                            set: { newSubcategoryTitles[parent.id] = $0 }
                        ))
                        .padding(.leading)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit {
                            guard
                                let title = newSubcategoryTitles[parent.id],
                                !title.trimmingCharacters(in: .whitespaces).isEmpty
                            else { return }
                            send(.createSubcategory(
                                title: title.trimmingCharacters(in: .whitespaces),
                                parentCategoryID: parent.id
                            ))
                            newSubcategoryTitles[parent.id] = ""
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Categories")
        .task { await send(.task).finish() }
    }

    private var newCategoryTextField: some View {
        TextField("New category", text: $newCategoryTitle)
            .bold()
            .submitLabel(.done)
            .autocorrectionDisabled()
            .onSubmit {
                guard !newCategoryTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                send(.createCategory(title: newCategoryTitle.trimmingCharacters(in: .whitespaces)))
                newCategoryTitle = ""
            }
    }
}

#Preview {
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
//        try $0.defaultDatabase.write { db in
//            try db.seedSampleData()
//        }
    }
    NavigationStack {
        CategoriesView(
            store: Store(initialState: CategoriesReducer.State()) {
                CategoriesReducer()
                    ._printChanges()
            }
        )
    }
}

