import SwiftUI
import PortSightKit
struct DesktopCard<Content: View>: View {
    var padding: CGFloat = 24
    var size: DesktopCardSize? = nil
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: size?.height, alignment: .topLeading)
            .background(DesktopTheme.card, in: DesktopTheme.surfaceShape)
            .overlay { DesktopTheme.surfaceShape.strokeBorder(DesktopTheme.border, lineWidth: 1) }
            .modifier(DesktopCardShadow())
    }
}

