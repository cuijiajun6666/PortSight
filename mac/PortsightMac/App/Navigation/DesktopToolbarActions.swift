import SwiftUI
import PortSightKit

/// The native group sizes itself to its buttons. The notification header stays
/// mounted, keeping the toolbar item's intrinsic width stable while its contents move.
struct DesktopToolbarActions: View {
    let isPresented: Bool
    let scopeTitle: String
    let unreadCount: Int
    var openNotifications: () -> Void
    var openSettings: () -> Void
    var markAllRead: () -> Void
    var closeNotifications: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            // Native glass buttons, matching the notification header's mark-read / close controls.
            HStack(spacing: 8) {
                Button(action: openNotifications) {
                    Label("通知", systemImage: "bell")
                        .frame(width: 24, height: 24)
                }
                .overlay(alignment: .topTrailing) {
                    if unreadCount > 0 {
                        Text(unreadCount, format: .number.grouping(.never))
                            .font(.system(size: 9, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(.red, in: Capsule())
                            .offset(x: 2, y: -2)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .help(isPresented ? "隐藏通知" : "显示通知")
                .accessibilityValue("\(unreadCount) 条未读，\(isPresented ? "已展开" : "已收起")")
                .accessibilityIdentifier("toolbar_notifications")

                Button(action: openSettings) {
                    Label("设置", systemImage: "gearshape")
                        .frame(width: 24, height: 24)
                }
                .help("设置")
                .accessibilityIdentifier("toolbar_settings")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .foregroundStyle(.primary)
            .controlSize(.large)
            .font(.system(size: 16, weight: .medium))
            .fixedSize()
            .padding(.trailing, 6)

            DesktopNotificationsHeader(scopeTitle: scopeTitle, unreadCount: unreadCount,
                                       markAllRead: markAllRead, close: closeNotifications)
                .frame(width: DesktopTheme.notificationsWidth)
                .allowsHitTesting(isPresented)
                .accessibilityHidden(!isPresented)
        }
        .offset(x: isPresented ? 0 : DesktopTheme.notificationsWidth)
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 52)
        .clipped()
        .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: isPresented)
    }
}
