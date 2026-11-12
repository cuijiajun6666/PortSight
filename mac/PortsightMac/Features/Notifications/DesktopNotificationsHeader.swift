import SwiftUI
import PortSightKit

/// The notification heading lives in the top toolbar, above the transparent panel.
struct DesktopNotificationsHeader: View {
    let scopeTitle: String
    let unreadCount: Int
    var markAllRead: () -> Void
    var close: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("通知").font(.headline)
                Text("\(scopeTitle) · \(unreadCount) 条未读")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .padding(.leading)
            Spacer(minLength: 8)
            Button(action: markAllRead) {
                Label("全部标为已读", systemImage: "checkmark.message")
                    .frame(width: 24, height: 24)
            }
                .disabled(unreadCount == 0)
                .help("将当前账户的通知全部标为已读")
                .accessibilityIdentifier("notifications_mark_read")
            Button(action: close) {
                Label("关闭通知", systemImage: "xmark")
                    .frame(width: 24, height: 24)
            }
                .help("关闭通知")
                .accessibilityIdentifier("notifications_close")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .foregroundStyle(.primary)
        .controlSize(.large)
        .font(.system(size: 16, weight: .medium))
        .accessibilityIdentifier("notifications_header")
    }
}
