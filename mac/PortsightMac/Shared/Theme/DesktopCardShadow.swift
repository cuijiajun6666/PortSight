import SwiftUI
import PortSightKit

/// A broad, soft shadow and a small contact shadow keep white cards distinct.
struct DesktopCardShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.06),
                    radius: 14, x: 0, y: 5)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.10 : 0.025),
                    radius: 3, x: 0, y: 1)
    }
}
