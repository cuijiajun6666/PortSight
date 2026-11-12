//
//  DesktopConnectionStatus.swift
//  PortsightMac
//
//  How this Mac reaches the Mac mini: 直连 / 通过中转 / 暂时连不上, with the route, latency, last sync and
//  the upload queue. Mirrors the iOS ConnectionStatusViews. Read-only.
//

import SwiftUI
import PortSightKit

extension ConnectionStatus.Path {
    var desktopTint: Color {
        switch self {
        case .direct: DesktopTheme.green
        case .relayed: DesktopTheme.orange
        case .offline: .red
        }
    }
}

extension ConnectionStatus {
    /// The connection this Mac uses, measured (ServerStore.connection): Tailscale Funnel, the last read's round
    /// trip, the last sync; the sample before pairing.
    static var desktop: ConnectionStatus { ServerStore.shared.connection }

    var latencyText: String { latencyMs.map { "\($0) ms" } ?? "—" }

    /// 悉尼 · 直连 · 9 ms
    var compactTitle: String {
        var parts = [serverPlace, path.title]
        if let latencyMs { parts.append("\(latencyMs) ms") }
        return parts.joined(separator: " · ")
    }
}

/// Compact status (dot + place · route · latency); click for the route diagram.
/// Until a server is paired (sample data or no host), it shows a neutral 尚未配对 instead of a route.
struct DesktopConnectionBadge: View {
    /// nil: this Mac's measured connection, kept current as the store reads.
    var status: ConnectionStatus? = nil
    @ObservedObject private var store = ServerStore.shared
    @State private var showDetails = false

    private var paired: Bool { !store.isSample && store.pairingState != .unpaired }
    /// Offline while the relay cannot be reached, so the badge never says 直连 next to 连不上服务器.
    private var shown: ConnectionStatus {
        if let status { return store.lastFailure != nil && store.failure == .network ? DemoConnection.ownerOffline : status }
        return store.connection
    }

    var body: some View {
        Button { showDetails.toggle() } label: {
            HStack(spacing: 6) {
                DesktopStatusDot(color: paired ? shown.path.desktopTint : .secondary, size: 8)
                if paired {
                    Text(shown.compactTitle)
                        .font(.system(size: 12, weight: .medium)).monospacedDigit()
                        .contentTransition(.numericText(value: Double(shown.latencyMs ?? 0)))
                        .animation(.smooth, value: shown.latencyMs)
                } else {
                    Text("尚未配对").font(.system(size: 12, weight: .medium))
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("服务器连接")
        .accessibilityLabel("服务器连接：" + (paired ? shown.path.title : "尚未配对"))
        .popover(isPresented: $showDetails, arrowEdge: .bottom) {
            DesktopConnectionDetail(status: shown, paired: paired).frame(width: 380)
        }
    }
}

/// Route diagram, advice and the connection facts.
struct DesktopConnectionDetail: View {
    let status: ConnectionStatus
    /// False until a server is paired: the facts read 配对后显示 instead of figures.
    var paired = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if paired {
                Label(status.path.title, systemImage: status.path.icon)
                    .font(.title3.bold()).foregroundStyle(status.path.desktopTint)
            } else {
                Label("尚未配对", systemImage: "link")
                    .font(.title3.bold()).foregroundStyle(.secondary)
            }
            route
            Text(paired ? status.advice : "Mac mini 到位并配对后显示线路、延迟和同步情况。")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            if paired { facts } else { pendingFacts }
            Text("通过 HTTPS 公网地址连接（Tailscale Funnel），设备上不用开 Tailscale。")
                .font(.footnote).foregroundStyle(.tertiary)
        }
        .padding(20)
    }

    private var pendingFacts: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(["延迟", "线路", "上次同步", "待上传"], id: \.self) { title in
                row(title) { Text("配对后显示").foregroundStyle(.secondary) }
            }
        }
        .font(.system(size: 13))
    }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            row("延迟") {
                Text(status.latencyMs.map { "\($0) ms · \(status.speedTitle)" } ?? "—")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(status.latencyMs ?? 0)))
                    .animation(.smooth, value: status.latencyMs)
            }
            row("线路") {
                Text(status.relayName.map { "经" + $0 } ?? (status.path == .direct ? "点对点直连" : "—"))
            }
            row("上次同步") { Text(status.lastSync.map { TerminalFormat.relative($0) } ?? "—") }
            row("待上传") {
                Text(status.queuedUploads == 0 ? "没有" : "\(status.queuedUploads) 项 · 夜间自动上传")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(status.queuedUploads)))
            }
        }
        .font(.system(size: 13))
    }

    private func row<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            value()
        }
    }

    /// 这台 Mac → (中转) → 悉尼 Mac mini
    private var route: some View {
        HStack(spacing: 8) {
            node("laptopcomputer", "这台 Mac")
            link
            if paired, let relay = status.relayName {
                node("arrow.triangle.branch", relay)
                link
            }
            node("macmini", paired ? status.serverPlace + " " + status.serverName : "Mac mini")
        }
    }

    private var link: some View {
        Rectangle()
            .fill(paired && status.path == .offline ? AnyShapeStyle(.red.opacity(0.5)) : AnyShapeStyle(.secondary.opacity(0.4)))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }

    private func node(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3).frame(width: 40, height: 40)
                .background(.quaternary, in: Circle())
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
        }
    }
}

/// Settings row: 服务器连接 with the compact status; click for details.
struct DesktopConnectionSettingsRow: View {
    /// nil: this Mac's measured connection.
    var status: ConnectionStatus? = nil

    var body: some View {
        LabeledContent("服务器连接") {
            DesktopConnectionBadge(status: status)
        }
    }
}
