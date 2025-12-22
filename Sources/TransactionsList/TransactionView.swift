import SwiftUI

struct TransactionView: View {
    let transaction: Transaction
    let category: String?
    let tags: [String]
    let location: TransactionLocation?

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

                if let location = location, let city = location.city, let countryName = location.countryDisplayName {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("\(city), \(countryName)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()

            ValueView(value: transaction.signedValue)
        }
    }
}
