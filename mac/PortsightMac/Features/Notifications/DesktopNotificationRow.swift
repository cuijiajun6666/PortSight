import SwiftUI
import PortSightKit

struct DesktopNotificationRow: View {
    let notice: DemoNotice
    let isRead: Bool
    let isAcknowledged: Bool

    /// Same mapping as the alert rows and the detail sheets (DesktopStatus.color).
    private var severityColor: Color { DesktopStatus.color(AlertSeverity(noticeSeverity: notice.severity)) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: notice.severity == "critical" ? "exclamationmark.circle.fill" : "bell.fill")
                .font(.caption)
                .foregroundStyle(severityColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(notice.title)
                    .fontWeight(isRead ? .regular : .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Text(notice.detail)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(notice.category + " · " + notice.time)
                    .font(.caption2).foregroundStyle(.secondary)
                if isAcknowledged {
                    Label("已确认", systemImage: "checkmark.seal")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if !isRead {
                Image(systemName: "circle.fill")
                    .font(.system(size: 5)).foregroundStyle(.blue)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
