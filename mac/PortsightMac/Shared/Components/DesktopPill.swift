import SwiftUI
import PortSightKit
struct DesktopPill: View {
    let text: String
    var color: Color = DesktopTheme.blue
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5).background(color.opacity(0.08), in: Capsule())
    }
}

