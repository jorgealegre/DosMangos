import Foundation

extension Money {
    /// Formatting styles for displaying monetary amounts.
    public enum FormatStyle: Sendable {
        /// Whole numbers with thousands separators (e.g., "10,932,123")
        case full
        /// Compact notation for large numbers (e.g., "~10.9M")
        /// - Under 100,000: shows full with separators
        /// - 100,000 to 999,999: shows as "~123K"
        /// - 1,000,000+: shows as "~1.2M"
        case compact
    }

    /// Formats the monetary amount using the specified style.
    /// - Parameters:
    ///   - style: The formatting style to use
    ///   - includeCurrencyCode: Whether to append the currency code (default: true)
    /// - Returns: A formatted string representation of the amount
    public func formatted(
        _ style: FormatStyle = .full,
        includeCurrencyCode: Bool = true
    ) -> String {
        let formattedAmount: String
        switch style {
        case .full:
            formattedAmount = formatFull()
        case .compact:
            formattedAmount = formatCompact()
        }

        if includeCurrencyCode {
            return "\(formattedAmount) \(currencyCode)"
        } else {
            return formattedAmount
        }
    }

    // MARK: - Private Formatting Methods

    private func formatFull() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true

        let number = NSDecimalNumber(decimal: amount)
        return formatter.string(from: number) ?? amount.description
    }

    private func formatCompact() -> String {
        let absoluteAmount = abs(amount)
        let isNegative = amount < 0
        let prefix = isNegative ? "-" : ""

        // Thresholds for compact notation
        let million = Decimal(1_000_000)
        let hundredThousand = Decimal(100_000)

        if absoluteAmount >= million {
            // Format as millions (e.g., "~1.2M")
            let millions = absoluteAmount / million
            return "~\(prefix)\(formatCompactNumber(millions))M"
        } else if absoluteAmount >= hundredThousand {
            // Format as thousands (e.g., "~123K")
            let thousands = absoluteAmount / Decimal(1_000)
            return "~\(prefix)\(formatCompactNumber(thousands))K"
        } else {
            // Under 100K: show full format
            return formatFull()
        }
    }

    private func formatCompactNumber(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false

        let number = NSDecimalNumber(decimal: value)
        return formatter.string(from: number) ?? value.description
    }
}

