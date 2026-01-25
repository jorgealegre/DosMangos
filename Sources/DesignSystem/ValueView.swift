import Currency
import Dependencies
import SwiftUI

struct ValueView: View {
    let money: Money
    var style: Money.FormatStyle = .full

    var body: some View {
        Text(money.formatted(style))
            .monospacedDigit()
            .bold()
            .foregroundStyle(money.value < 0 ? Color.expense : .income)
            .contentTransition(.numericText())
    }
}
