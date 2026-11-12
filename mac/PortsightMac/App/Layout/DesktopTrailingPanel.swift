import SwiftUI
import PortSightKit

/// Reveals a transparent trailing panel by giving it space beside the main content.
struct DesktopTrailingPanel<MainContent: View, PanelContent: View>: View {
    let isPresented: Bool
    var panelWidth: CGFloat = DesktopTheme.notificationsWidth
    @ViewBuilder var content: MainContent
    @ViewBuilder var panel: PanelContent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            content
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)

            DesktopTrailingReveal(isPresented: isPresented, width: panelWidth) {
                panel.frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: isPresented)
    }
}
