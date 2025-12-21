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

    var subcategoriesByParent: [String: [Category]] {
        Dictionary(grouping: categories.filter { $0.parentCategoryID != nil }) { category in
            category.parentCategoryID!
        }
    }

    var parentCategories: [Category] {
        categories.filter { $0.parentCategoryID == nil }
            .sorted { $0.title < $1.title }
    }

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
                // Grouped sections for parents with children
                ForEach(parentCategories) { parent in
                    let subcategories = subcategoriesByParent[parent.title] ?? []
                    if !subcategories.isEmpty {
                        Section(parent.title) {
                            // Parent category row
                            CategoryRow(
                                isSelected: selectedCategoryIDs.contains(parent.id),
                                selectedCategories: $selectedCategories,
                                category: parent
                            )
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    deleteButtonTapped(category: parent)
                                }
                                Button("Edit") {
                                    editButtonTapped(category: parent)
                                }
                            }
                            // Subcategory rows
                            ForEach(subcategories.sorted { $0.title < $1.title }) { subcategory in
                                CategoryRow(
                                    isSelected: selectedCategoryIDs.contains(subcategory.id),
                                    selectedCategories: $selectedCategories,
                                    category: subcategory
                                )
                                .swipeActions {
                                    Button("Delete", role: .destructive) {
                                        deleteButtonTapped(category: subcategory)
                                    }
                                    Button("Edit") {
                                        editButtonTapped(category: subcategory)
                                    }
                                }
                            }
                        }
                    } else {
                        // Standalone parent (no children)
                        Section {
                            CategoryRow(
                                isSelected: selectedCategoryIDs.contains(parent.id),
                                selectedCategories: $selectedCategories,
                                category: parent
                            )
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    deleteButtonTapped(category: parent)
                                }
                                Button("Edit") {
                                    editButtonTapped(category: parent)
                                }
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
                // Single-select: clear previous selection and select new one
                selectedCategories.removeAll()
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

