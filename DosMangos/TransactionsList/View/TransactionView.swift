import SwiftUI

struct TransactionView: View {
    let transaction: Transaction
    @State private var categories: [Category] = []
    @State private var tags: [Tag] = []
    
    @Dependency(\.defaultDatabase) private var database

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(transaction.description)")
                        .font(.title2)
                    Spacer()
                }
                
                if !categories.isEmpty || !tags.isEmpty {
                    HStack(spacing: 4) {
                        if !categories.isEmpty {
                            ForEach(categories) { category in
                                Text(category.title)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                        
                        if !tags.isEmpty {
                            ForEach(tags) { tag in
                                Text("#\(tag.title)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Spacer()

            ValueView(value: transaction.value)
        }
        .task {
            await loadCategoriesAndTags()
        }
    }
    
    private func loadCategoriesAndTags() async {
        await withErrorReporting {
            let fetchedCategories = try await database.read { db in
                try Category
                    .join(TransactionCategory.all) { $0.title.eq($1.categoryID) }
                    .where { $1.transactionID.eq(transaction.id) }
                    .select { category, _ in category }
                    .fetchAll(db)
            }
            
            let fetchedTags = try await database.read { db in
                try Tag
                    .join(TransactionTag.all) { $0.title.eq($1.tagID) }
                    .where { $1.transactionID.eq(transaction.id) }
                    .select { tag, _ in tag }
                    .fetchAll(db)
            }
            
            self.categories = fetchedCategories
            self.tags = fetchedTags
        }
    }
}

//struct TransactionView_Previews: PreviewProvider {
//    static var previews: some View {
//        VStack(spacing: 0) {
////            TransactionView(transaction: .mock())
////            TransactionView(transaction: .mock())
////            TransactionView(transaction: .mock())
//        }
//        .padding()
//    }
//}
