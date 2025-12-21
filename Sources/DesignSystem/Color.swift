import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .displayP3,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            opacity: alpha
        )
    }
}

extension Color {
    static var income: Color {
        Color(hex: 0x9BD770)
    }

    static var expense: Color {
        Color(hex: 0xFE8176)
    }
}
