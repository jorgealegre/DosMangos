import Currency
import Dependencies
import SwiftUI

struct ValueView: View {
    let money: Money

    var body: some View {
        Text("\(money.amount.description) \(money.currencyCode)")
            .monospacedDigit()
            .bold()
            .foregroundStyle(money.value < 0 ? Color.expense : .income)
            .contentTransition(.numericText())
    }
}
