import SwiftUI

/// A text field that displays an integer with locale-aware thousands separators.
/// Uses pure SwiftUI with onChange for formatting - no UIKit required.
struct FormattedIntegerField: View {
    @Binding var value: Int
    @State private var text: String = ""
    
    /// Maximum allowed value (~1 trillion, well within Int range)
    private let maxValue = 999_999_999_999
    
    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()
    
    var body: some View {
        TextField("0", text: $text)
            .font(.system(size: 80, weight: .bold))
            .minimumScaleFactor(0.2)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .keyboardType(.numberPad)
            .onChange(of: text) { _, newText in
                processInput(newText)
            }
            .onAppear {
                // Initialize text from value
                text = format(value)
            }
    }
    
    private func processInput(_ newText: String) {
        // Extract only digits
        let digits = newText.filter { $0.isNumber }
        
        // Handle empty
        if digits.isEmpty {
            value = 0
            text = ""
            return
        }
        
        // Parse to integer
        guard let parsed = Int(digits), parsed <= maxValue else {
            // Number too large or can't parse - restore previous formatted value
            text = format(value)
            return
        }
        
        // Update value binding
        value = parsed
        
        // Format and update text
        let formatted = format(parsed)
        if text != formatted {
            text = formatted
        }
    }
    
    private func format(_ number: Int) -> String {
        guard number != 0 else { return "" }
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

#Preview {
    struct Preview: View {
        @State private var amount = 1234567
        @FocusState private var isFocused: Bool
        
        var body: some View {
            VStack(spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Button("USD") {}
                        .buttonStyle(.borderedProminent)
                    
                    FormattedIntegerField(value: $amount)
                        .focused($isFocused)
                }
                .padding()
                
                Text("Value: \(amount)")
                
                Button("Set to 999,999") { amount = 999_999 }
                Button("Focus") { isFocused = true }
            }
            .onAppear { isFocused = true }
        }
    }
    return Preview()
}
