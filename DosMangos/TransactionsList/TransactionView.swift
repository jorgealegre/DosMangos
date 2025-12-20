import SwiftUI

struct TransactionView: View {
    let transaction: Transaction
    let categories: [String]
    let tags: [String]

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
                            ForEach(categories, id: \.self) { category in
                                Text(category)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }

                        if !tags.isEmpty {
                            ForEach(tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Spacer()

            ValueView(value: transaction.signedValue)
        }
    }
}
