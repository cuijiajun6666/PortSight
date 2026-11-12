import SwiftUI
import PortSightKit

/// One window-level material remains visible behind the toolbar and both side rails.
struct DesktopWindowBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .containerBackground(.ultraThinMaterial, for: .window)
    }
}
