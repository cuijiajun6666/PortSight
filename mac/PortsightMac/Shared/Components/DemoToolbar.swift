import SwiftUI
import PortSightKit
struct DemoToolbar: ToolbarContent {
    @EnvironmentObject private var demo: PortfolioDemo
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) { DemoScopeMenu() }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { withAnimation { demo.showNotifications = true } } label: {
                Image(systemName: demo.notices.contains { !demo.read.contains($0.id) } ? "bell.badge" : "bell")
            }.accessibilityLabel("通知")
            Button { demo.showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("设置")
        }
    }
}
