import Currency
import Dependencies
import SwiftUI

struct ValueView: View {
    let value: USD

    @Dependency(\.locale) private var locale

    var body: some View {
        Text("\(value.localizedString(for: locale))")
            .monospacedDigit()
            .bold()
            .foregroundStyle(value < 0 ? Color.expense : .income)
            .contentTransition(.numericText())
    }
}
