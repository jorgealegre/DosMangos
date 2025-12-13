import SQLiteData
import SwiftUI
import SwiftUINavigation

struct CategoriesView: View {
    @FetchAll(Category.order(by: \.title)) var categories
    @Binding var selectedCategories: [Category]
    @State var editingCategory: Category.Draft?
    @State var categoryTitle = ""

    @Dependency(\.defaultDatabase) var database
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            let selectedCategoryIDs = Set(selectedCategories.map(\.id))
            Section {
                Button("New category") {
                    categoryTitle = ""
                    editingCategory = Category.Draft()
                }
            }
            if !categories.isEmpty {
                Section {
                    ForEach(categories) { category in
                        CategoryRow(
                            isSelected: selectedCategoryIDs.contains(category.id),
                            selectedCategories: $selectedCategories,
                            category: category
                        )
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                deleteButtonTapped(category: category)
                            }
                            Button("Edit") {
                                editButtonTapped(category: category)
                            }
                        }
                    }
                }
            }
        }
        .alert(item: $editingCategory) { item in
            Text(item.title == nil ? "New category" : "Edit category")
        } actions: { item in
            TextField("Category name", text: $categoryTitle)
            Button("Save") {
                saveButtonTapped()
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Done") { dismiss() }
            }
        }
        .navigationTitle(Text("Categories"))
    }

    func deleteButtonTapped(category: Category) {
        withErrorReporting {
            try database.write { db in
                try Category.where { $0.title.eq(category.title) }.delete().execute(db)
            }
        }
    }

    func editButtonTapped(category: Category) {
        categoryTitle = category.title
        editingCategory = Category.Draft(category)
    }

    func saveButtonTapped() {
        defer { categoryTitle = "" }
        let category = Category(title: categoryTitle)
        withErrorReporting {
            try database.write { db in
                if let existingCategoryTitle = editingCategory?.title {
                    selectedCategories.removeAll(where: { $0.title == existingCategoryTitle })
                    try Category
                        .update { $0.title = categoryTitle }
                        .where { $0.title.eq(existingCategoryTitle) }
                        .execute(db)
                } else {
                    try Category.insert(or: .ignore) { category }
                        .execute(db)
                }
            }
            selectedCategories.append(category)
        }
    }
}

private struct CategoryRow: View {
    let isSelected: Bool
    @Binding var selectedCategories: [Category]
    let category: Category

    var body: some View {
        Button {
            if isSelected {
                selectedCategories.removeAll(where: { $0.id == category.id })
            } else {
                selectedCategories.append(category)
            }
        } label: {
            HStack {
                if isSelected {
                    Image(systemName: "checkmark")
                }
                Text(category.title)
            }
        }
        .tint(isSelected ? .accentColor : .primary)
    }
}

#Preview {
    @Previewable @State var categories: [Category] = []
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
    }

    NavigationStack {
        CategoriesView(selectedCategories: $categories)
    }
}

