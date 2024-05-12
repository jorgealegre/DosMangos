import SwiftUI

struct ValueView: View {
    let value: Int

    var body: some View {
        Text("$\(value.formatted())")
            .monospacedDigit()
            .bold()
            .foregroundColor(value < 0 ? .expense : .income)
    }
}
