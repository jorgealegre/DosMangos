import Currency
import Dependencies
import SwiftUI

struct ValueView: View {
    let value: USD

    var body: some View {
        Text("\(value.roundedAmount.description) \(type(of: value).alphabeticCode)")
            .monospacedDigit()
            .bold()
            .foregroundStyle(value < 0 ? Color.expense : .income)
            .contentTransition(.numericText())
    }
}
