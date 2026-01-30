import Collections
import ComposableArchitecture
import SQLiteData
import SwiftUI

@Reducer
struct CategoriesReducer: Reducer {

    struct CategoryRequest: FetchKeyRequest, Equatable {
        struct Value: Equatable {
            var categories: OrderedDictionary<Category, [Subcategory]> = [:]
        }

        func fetch(_ db: Database) throws -> Value {
            let allCategories = try AllCategories
                .order { ($0.categoryID, $0.subcategoryTitle) }
                .fetchAll(db)

            let result = allCategories.reduce(into: OrderedDictionary<Category, [Subcategory]>()) { dict, row in
                let category = Category(title: row.categoryID)
                if let subcategoryID = row.subcategoryID, let subcategoryTitle = row.subcategoryTitle {
                    dict[category, default: []].append(
                        Subcategory(id: subcategoryID, title: subcategoryTitle, categoryID: category.id)
                    )
                } else {
                    dict[category] = []
                }
            }
            return Value(categories: result)
        }
    }

    @ObservableState
    struct State: Equatable {
        @Fetch(CategoryRequest(), animation: .default)
        var categories = CategoryRequest.Value()


        init() {
        }
    }

    enum Action: ViewAction {
        enum View {
            case task
            case createCategory(title: String)
            case createSubcategory(title: String, categoryID: Category.ID)
            case deleteCategory(id: Category.ID)
            case deleteSubcategory(id: Subcategory.ID)
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

                case let .createSubcategory(title, categoryID):
                    // TODO: I might want to keep the text field filled in and show an error message if there's a unique constraint error for example
                    return .run { _ in
                        do {
                            try database.write { db in
                                try Subcategory.insert {
                                    Subcategory.Draft(title: title, categoryID: categoryID)
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

                case let .deleteSubcategory(id):
                    return .run { _ in
                        withErrorReporting {
                            try database.write { db in
                                try Subcategory.find(id)
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

                ForEach(store.categories.categories.elements, id: \.key) { category, subcategories in
                    Section {
                        Text(category.title)
                            .bold()
                            .swipeActions {
                                Button(role: .destructive) {
                                    send(.deleteCategory(id: category.id))
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        ForEach(subcategories) { subcategory in
                            Text("• " + subcategory.title)
                                .padding(.leading)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        send(.deleteSubcategory(id: subcategory.id))
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                        TextField("New subcategory for \(category.title)", text: Binding(
                            get: { newSubcategoryTitles[category.id] ?? "" },
                            set: { newSubcategoryTitles[category.id] = $0 }
                        ))
                        .padding(.leading)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit {
                            guard
                                let title = newSubcategoryTitles[category.id],
                                !title.trimmingCharacters(in: .whitespaces).isEmpty
                            else { return }
                            send(.createSubcategory(
                                title: title.trimmingCharacters(in: .whitespaces),
                                categoryID: category.id
                            ))
                            newSubcategoryTitles[category.id] = ""
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

