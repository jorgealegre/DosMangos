import Currency
import SharedModels
import SwiftUI

struct ValueView: View {
    let value: USD

    var body: some View {
        Text("\(value.localizedString())")
            .monospacedDigit()
            .bold()
            .foregroundStyle(value < 0 ? Color.expense : .income)
            .contentTransition(.numericText())
    }
}
