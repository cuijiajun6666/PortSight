import SwiftUI
import PortSightKit

extension DesktopTheme {
    /// `part / whole` as a signed percentage; 「—」 when `whole` is 0 (never a division by zero).
    static func percent(_ part: Double, of whole: Double) -> String {
        guard whole != 0, part.isFinite, whole.isFinite else { return "—" }
        return percent(part / whole)
    }

    /// `part / whole` as an unsigned share ("12.3%"); 「—」 when `whole` is 0.
    static func share(_ part: Double, of whole: Double, digits: Int = 1) -> String {
        guard whole != 0, part.isFinite, whole.isFinite else { return "—" }
        return String(format: "%.\(digits)f%%", part / whole * 100)
    }
}

/// One short secondary line where a chart or list has nothing to draw (e.g. 「暂无持仓」).
struct DesktopMissingNote: View {
    let text: String
    /// The height of the chart it replaces (nil: its own height).
    var height: CGFloat?

    init(_ text: String, height: CGFloat? = nil) {
        self.text = text
        self.height = height
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .accessibilityIdentifier("missing_note")
    }
}
