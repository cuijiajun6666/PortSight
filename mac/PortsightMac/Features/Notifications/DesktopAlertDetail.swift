import SwiftUI
import PortSightKit

/// Detail sheet for a relay alert opened from the bell's notification panel. Opening it marks the alert read.
struct DesktopAlertDetail: View {
    @EnvironmentObject private var terminal: TerminalDemo
    let alert: TerminalAlert

    var body: some View {
        DesktopMessageDetail(
            severity: alert.severity,
            category: alert.category.title,
            categoryIcon: alert.category.icon,
            title: alert.title,
            message: alert.detail,
            meta: [alert.source, TerminalFormat.relative(alert.at)],
            facts: [.init(label: "时间", value: alert.at.formatted(date: .abbreviated, time: .shortened)),
                    .init(label: "编号", value: alert.id)],
            note: "告警只用于查看，App 不会停止、重启或修改任何任务。"
        )
        .onAppear { terminal.read.insert(alert.id) }
    }
}
