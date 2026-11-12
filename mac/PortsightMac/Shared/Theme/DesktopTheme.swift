import SwiftUI
import AppKit
import PortSightKit

enum DesktopTheme {
    static let surfaceCornerRadius: CGFloat = 20
    static let notificationsWidth: CGFloat = 310
    static var surfaceShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
    }

    static let blue = Color(red: 0.26, green: 0.43, blue: 0.85)
    static let green = Color(red: 0.12, green: 0.61, blue: 0.44)
    static let orange = Color(red: 0.87, green: 0.53, blue: 0.28)
    /// System yellow in dark mode; a deeper yellow in light mode so text stays readable.
    static let yellow = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .systemYellow : NSColor(red: 0.64, green: 0.46, blue: 0, alpha: 1)
    })
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let border = Color.primary.opacity(0.055)
    static func money(_ value: Double, decimals: Int = 2) -> String {
        value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")).precision(.fractionLength(decimals)))
    }
    static func signedMoney(_ value: Double) -> String { (value >= 0 ? "+" : "−") + money(abs(value)) }
    static func percent(_ fraction: Double) -> String { String(format: "%+.2f%%", fraction * 100) }
    static func pnlColor(_ value: Double) -> Color { value >= 0 ? green : .red }
    static func symbolColor(_ symbol: String) -> Color {
        switch symbol {
        case "NVDA": green
        case "AAPL": .primary
        case "BTC": orange
        case "ETH": .indigo
        case "SPY": blue
        case "QQQ": .purple
        case "TLT": .cyan
        default: blue
        }
    }
}

