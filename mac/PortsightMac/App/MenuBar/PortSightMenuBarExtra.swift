import SwiftUI
import PortSightKit

/// Menu bar status (plan §4 P1): server state in the icon, money and the latest alerts in the window.
/// The label lives as long as the app, so it also refreshes the paired relay every minute (unpaired, the store
/// keeps the sample and sends nothing) and opens the clicked push's event (or 服务器 for any other notification).
struct PortSightMenuBarLabel: View {
    @ObservedObject var store: ServerStore
    @ObservedObject var router: DesktopRouter
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: symbol).accessibilityLabel("PortSight · " + title)
            .task {
                while !Task.isCancelled {
                    await store.refresh()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .portSightOpenServer)) { note in
                router.pending = (note.object as? PushEventRef).map { .event($0) } ?? .section(.server)
                if !PortsightMacApp.showMainWindow() { openWindow(id: PortsightMacApp.mainWindowID) }
                NSApplication.shared.activate()
            }
    }

    private var symbol: String { store.menuBarStatus().symbol }
    private var title: String { store.menuBarStatus().title }
}

extension ServerStore {
    /// The menu bar's state, in the same order as the server page's banner: a repair, no pairing, no data, a stale
    /// heartbeat or an unreachable relay come before the host's own summary.
    func menuBarStatus(now: Date = .now) -> (title: String, symbol: String, color: Color) {
        if pairingState == .needsRepair { return ("需要重新配对", "exclamationmark.triangle", DesktopTheme.orange) }
        if isSample || pairingState == .unpaired { return ("尚未配对", "macmini", .secondary) }
        if let problem = connectionBanner(now: now, networkHint: "网络") {
            let symbol = switch problem.kind {
            case .offline: "wifi.exclamationmark"
            case .rateLimited: "hourglass"
            case .serverError, .stale: "exclamationmark.triangle"
            }
            return (problem.title, symbol, problem.kind == .stale ? .red : DesktopTheme.orange)
        }
        guard let host else { return ("正在读取", "macmini", .secondary) }
        if !host.hasData { return ("暂无数据", "macmini", .secondary) }
        let state = host.summary?.state
        switch state {
        case "ok": return ("运行正常", "macmini", DesktopStatus.color(relay: state))
        case "critical": return ("出现严重问题", "exclamationmark.octagon", DesktopStatus.color(relay: state))
        default: return ("需要留意", "exclamationmark.triangle", DesktopStatus.color(relay: state))
        }
    }

    /// The host's own figures are worth showing (paired, real data).
    var showsHostFigures: Bool { !isSample && pairingState != .unpaired && host?.hasData == true }
}

struct PortSightMenuBarContent: View {
    @ObservedObject var store: ServerStore
    @ObservedObject var terminal: TerminalDemo
    @ObservedObject var router: DesktopRouter
    @Environment(\.openWindow) private var openWindow

    // 全部: the built-in portfolio before pairing; once paired the personal IBKR account's real figures plus the
    // built-in quant account (Portfolio).
    private var total: Double { Portfolio.total(.all) }
    private var day: Double { Portfolio.dayPnL(.all) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                let status = store.menuBarStatus()
                DesktopStatusDot(color: status.color, size: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text((store.host?.host?.hostname ?? "Mac mini") + " · " + status.title).font(.system(size: 13, weight: .semibold))
                    Text(store.showsHostFigures
                         ? "心跳异常 \(store.host?.summary?.heartbeats_problem ?? 0) · 更新于 " + ServerDates.clock(ServerDates.parse(store.host?.as_of))
                         : "暂无")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("总资产").font(.system(size: 10)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(DesktopTheme.money(total)).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                    Spacer()
                    Text("今日 " + DesktopTheme.signedMoney(day)).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesktopTheme.pnlColor(day)).monospacedDigit()
                }
                if let note = Portfolio.note(.all) {
                    Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("活跃告警").font(.system(size: 10)).foregroundStyle(.secondary)
                ForEach(terminal.alerts.filter { $0.severity != .info }.prefix(5)) { alert in
                    Button { show(nil, notifications: true) } label: {
                        DesktopAlertRow(alert: alert, isRead: terminal.read.contains(alert.id), compact: true)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button { show(.remote) } label: { Label("远程桌面", systemImage: "rectangle.on.rectangle") }
                Button { show(.cloud) } label: { Label("Immich", systemImage: "photo.stack") }
                Button { show(.ai) } label: { Label("AI 控制台", systemImage: "brain") }
            }
            .buttonStyle(.glass).controlSize(.small)

            HStack {
                Button("打开 PortSight") { show(nil) }.buttonStyle(.glassProminent)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }.buttonStyle(.glass)
            }
            .controlSize(.regular)
        }
        .padding(16)
        .frame(width: 340)
    }

    private func show(_ section: DesktopSection?, notifications: Bool = false) {
        router.pending = notifications ? .notifications : section.map { .section($0) }
        // The existing main window takes the route; a second window only when there is none.
        if !PortsightMacApp.showMainWindow() { openWindow(id: PortsightMacApp.mainWindowID) }
        NSApplication.shared.activate()
    }
}
