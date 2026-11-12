import SwiftUI
import Charts
import PortSightKit
struct DemoCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) { Image(systemName: icon).foregroundStyle(.secondary); Text(title).font(.headline); Spacer() }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: DesktopTheme.surfaceShape)
        .modifier(DesktopCardShadow())
    }
}
