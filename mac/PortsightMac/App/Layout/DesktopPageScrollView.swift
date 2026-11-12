import SwiftUI
import PortSightKit

/// Page content meets every edge of the shared rounded scroll surface.
struct DesktopPageScrollView<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .contentMargins(.vertical, 0, for: .scrollContent)
        .scrollEdgeEffectHidden(true, for: .all)
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("desktop_scroll")
    }
}
