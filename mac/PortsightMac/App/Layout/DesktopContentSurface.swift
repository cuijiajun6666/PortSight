import SwiftUI
import PortSightKit

/// An opaque content panel covers the shared glass, including its scrolling edges.
/// Its corners follow the window's own corner radius (concentric with the 3pt inset to the window edge),
/// the same on all four corners; 20pt is the fallback when the window shape is not known.
/// Card pages pass `opaque: false`: their white cards then sit on the window glass instead of a white panel.
struct DesktopContentSurface: ViewModifier {
    var opaque = true
    private let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(DesktopTheme.surfaceCornerRadius)),
                                            isUniform: true)

    func body(content: Content) -> some View {
        content
            .background(opaque ? DesktopTheme.card : Color.clear)
            .clipShape(shape)
            .padding([.trailing, .bottom], 3)
    }
}
