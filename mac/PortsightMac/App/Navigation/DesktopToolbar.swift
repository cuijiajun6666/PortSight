import SwiftUI
import PortSightKit

/// Standard macOS toolbar controls; the system supplies their glass appearance.
struct DesktopToolbar: ToolbarContent {
    @EnvironmentObject private var demo: PortfolioDemo
    @EnvironmentObject private var terminal: TerminalDemo
    let section: DesktopSection
    @Binding var tab: DesktopTab
    var openNotifications: () -> Void
    var openSettings: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Text(section.title)
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1)
                .help(section.subtitle)
                .accessibilityIdentifier("desktop_page_title")
        }
        .sharedBackgroundVisibility(.hidden)
        // Always present so the trailing buttons keep their place; on sections with nothing to show here
        // (远程) it is an invisible spacer without the glass capsule.
        ToolbarItem(placement: .principal) {
            HStack(spacing: 10) {
                if !section.tabGroups.isEmpty {
                    DesktopSectionTabs(groups: section.tabGroups, selection: $tab)
                }
                if !section.tabGroups.isEmpty && section.usesScope {
                    Divider().frame(height: 16)
                }
                // Only sections that really split money by account show 全部 / 个人 / 量化.
                if section.usesScope {
                    DesktopCapsulePicker(title: "资产范围", options: PortfolioScope.allCases, selection: $demo.scope) { $0.rawValue }
                    .labelsHidden()
                    .accessibilityIdentifier("portfolio_scope")
                    .help("资产范围")
                }
                if section.tabGroups.isEmpty && !section.usesScope {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                }
            }
        }
        .sharedBackgroundVisibility(section.tabGroups.isEmpty && !section.usesScope ? .hidden : .automatic)
        ToolbarItem(placement: .primaryAction) {
            DesktopToolbarActions(
                isPresented: demo.showNotifications,
                scopeTitle: demo.bellScope(on: section).rawValue,
                unreadCount: demo.bellNotices(on: section).filter { !demo.read.contains($0.id) }.count + terminal.unreadCount,
                openNotifications: openNotifications,
                openSettings: openSettings,
                markAllRead: {
                    demo.read.formUnion(demo.bellNotices(on: section).map(\.id))
                    terminal.markAllRead()
                },
                closeNotifications: { demo.showNotifications = false }
            )
        }
        .sharedBackgroundVisibility(.hidden)
    }
}
