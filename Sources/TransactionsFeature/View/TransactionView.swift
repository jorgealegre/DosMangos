import SharedModels
import SwiftUI

struct TransactionView: View {
    let transaction: SharedModels.Transaction

    var body: some View {
        HStack {
            VStack {
                HStack {
                    Text("\(transaction.description)")
                        .font(.title2)
                    Spacer()
                }
            }
            Spacer()

            ValueView(value: transaction.value)
        }
    }
}

struct TransactionView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            TransactionView(transaction: .mock())
            TransactionView(transaction: .mock())
            TransactionView(transaction: .mock())
        }
        .padding()
    }
}
