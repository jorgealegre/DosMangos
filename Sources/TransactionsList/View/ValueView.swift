import SwiftUI

struct ValueView: View {
    let value: Int

    var body: some View {
        Text("\(value as NSValue, formatter: NumberFormatter.currencyWithoutUSPrefix)")
            .monospacedDigit()
            .bold()
            .foregroundStyle(value < 0 ? Color.expense : .income)
            .contentTransition(.numericText())
    }
}

extension NumberFormatter {
    static let currencyWithoutUSPrefix: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.locale = Locale(identifier: "en_US")
        formatter.currencySymbol = "$"
        return formatter
    }()
}
