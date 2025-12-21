import SwiftUI

struct TransactionView: View {
    let transaction: Transaction
    let category: String?
    let tags: [String]

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(transaction.description)")
                        .font(.title2)
                    Spacer()
                }

                HStack(spacing: 4) {
                    if let category {
                        Text(category)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }

                    ForEach(tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()

            ValueView(value: transaction.signedValue)
        }
    }
}
