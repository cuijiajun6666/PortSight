//
//  ConnectionStatusViews.swift
//  PortSight
//
//  How this phone reaches the Mac mini in Sydney: 直连 / 通过中转 / 暂时连不上, with latency, the relay used,
//  the last sync and the upload queue. Demo values until Tailscale's local status is wired in.
//

import SwiftUI
import PortSightKit

extension ConnectionStatus.Path {
    var tint: Color {
        switch self {
        case .direct: .green
        case .relayed: .orange
        case .offline: .red
        }
    }
}

/// Toolbar item: a status dot and the latency; tap for details.
struct ConnectionToolbarButton: View {
    let status: ConnectionStatus
    @State private var showDetails = false

    var body: some View {
        Button { showDetails = true } label: {
            HStack(spacing: 6) {
                Circle().fill(status.path.tint).frame(width: 8, height: 8)
                Text(status.latencyMs.map { "\($0) ms" } ?? status.path.title)
                    .contentTransition(.numericText(value: Double(status.latencyMs ?? 0)))
                    .animation(.smooth, value: status.latencyMs)
                    .font(.subheadline.weight(.medium)).monospacedDigit()
            }
            .padding(.horizontal, 4)
        }
        .accessibilityLabel("服务器连接：" + status.path.title)
        .sheet(isPresented: $showDetails) { ConnectionDetailView(status: status) }
    }
}

struct ConnectionDetailView: View {
    let status: ConnectionStatus
    /// As a sheet it brings its own navigation bar and 完成; pushed from settings it uses the stack's.
    var inSheet = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if inSheet {
            NavigationStack {
                list.toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            }
            .presentationDetents([.medium, .large])
        } else {
            list
        }
    }

    private var list: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Label(status.path.title, systemImage: status.path.icon)
                        .font(.title3.bold()).foregroundStyle(status.path.tint)
                    route
                    Text(status.advice).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            Section {
                LabeledContent("延迟") {
                    Text(status.latencyMs.map { "\($0) ms · \(status.speedTitle)" } ?? "—").monospacedDigit()
                        .contentTransition(.numericText(value: Double(status.latencyMs ?? 0)))
                        .animation(.smooth, value: status.latencyMs)
                }
                LabeledContent("线路", value: status.relayName.map { "经" + $0 } ?? (status.path == .direct ? "点对点直连" : "—"))
                LabeledContent("上次同步", value: status.lastSync.map { TerminalFormat.relative($0) } ?? "—")
                LabeledContent("待上传", value: status.queuedUploads == 0 ? "没有" : "\(status.queuedUploads) 项 · 夜间自动上传")
            } footer: {
                Text("通过 HTTPS 公网地址连接（Tailscale Funnel），设备上不用开 Tailscale。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("服务器连接")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 这台手机 → (中转) → 悉尼 Mac mini
    private var route: some View {
        HStack(spacing: 8) {
            node("iphone", "这台手机")
            link
            if let relay = status.relayName {
                node("arrow.triangle.branch", relay)
                link
            }
            node("macmini", status.serverPlace + " " + status.serverName)
        }
    }

    private var link: some View {
        Rectangle()
            .fill(status.path == .offline ? AnyShapeStyle(.red.opacity(0.5)) : AnyShapeStyle(.secondary.opacity(0.4)))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }

    private func node(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3).frame(width: 40, height: 40)
                .background(.quaternary, in: Circle())
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).fixedSize()
        }
    }
}

/// Settings row: status dot, route and latency; opens the details.
struct ConnectionSettingsRow: View {
    let status: ConnectionStatus

    var body: some View {
        NavigationLink {
            ConnectionDetailView(status: status, inSheet: false)
        } label: {
            LabeledContent {
                Text(status.latencyMs.map { "\($0) ms" } ?? "—").monospacedDigit()
            } label: {
                Label {
                    Text(status.serverPlace + " · " + status.path.title)
                } icon: {
                    Circle().fill(status.path.tint).frame(width: 9, height: 9)
                }
            }
        }
    }
}
