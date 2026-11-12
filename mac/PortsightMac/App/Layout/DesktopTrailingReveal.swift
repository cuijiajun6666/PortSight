import SwiftUI
import PortSightKit

/// A fixed-width view slides in as its visible area grows from the trailing edge.
struct DesktopTrailingReveal<Content: View>: View {
    let isPresented: Bool
    var width: CGFloat = DesktopTheme.notificationsWidth
    var allowsTopOverflow = false
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .frame(width: width)
            .frame(width: isPresented ? width : 0, alignment: .leading)
            .clipShape(TrailingRevealClip(allowsTopOverflow: allowsTopOverflow))
            .allowsHitTesting(isPresented)
            .accessibilityHidden(!isPresented)
            .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: isPresented)
    }
}

/// Retain horizontal reveal clipping while letting the notification scroll content
/// reach behind the titlebar. The native window remains the final outer boundary.
private struct TrailingRevealClip: Shape {
    let allowsTopOverflow: Bool

    func path(in rect: CGRect) -> Path {
        let extensionHeight = allowsTopOverflow ? rect.height : 0
        return Path(CGRect(x: rect.minX, y: rect.minY - extensionHeight,
                           width: rect.width, height: rect.height + extensionHeight))
    }
}
