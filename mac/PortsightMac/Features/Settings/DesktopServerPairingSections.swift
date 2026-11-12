//
//  DesktopServerPairingSections.swift
//  PortsightMac
//
//  设置 → 量化服务器: pair with the Mac mini's relay (HTTPS address + one-time code), see the pairing state, unpair,
//  and switch APNs pushes on or off. The device token lives only in this Mac's keychain.
//

import SwiftUI
import PortSightKit

struct DesktopServerPairingSections: View {
    @ObservedObject private var store = ServerStore.shared
    @State private var url = ""
    @State private var code = ""
    @AppStorage(ServerPushSettings.enabledKey) private var pushEnabled = false

    var body: some View {
        Group {
            Section {
                LabeledContent("状态") { DesktopPairingStateLabel(state: store.pairingState) }
                TextField("服务器地址", text: $url, prompt: Text("https://mac-mini.xxxx.ts.net"))
                    .autocorrectionDisabled()
                SecureField("配对码", text: $code)
                HStack {
                    if let message = store.message {
                        Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if store.busy { ProgressView().controlSize(.small) }
                    Button(store.isPaired ? "重新配对" : "配对") {
                        Task { if await store.pair(url: url, code: code) { code = "" } }
                    }
                    .disabled(store.busy || url.trimmingCharacters(in: .whitespaces).isEmpty
                              || code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if store.isPaired {
                    LabeledContent("已配对", value: store.baseURL)
                    Button("断开", role: .destructive) { Task { await store.forget() } }
                }
                DesktopConnectionSettingsRow()
            } header: {
                Text("量化服务器")
            } footer: {
                Text("家里的 Mac mini：主机状态、告警和推送都从这里连。在 Mac mini 上运行 python3 -m quant_system.relay pair 得到配对码，5 分钟内有效，只能用一次。只连 https:// 地址，这台 Mac 上不用开 Tailscale 或 VPN。设备凭证只存在这台 Mac 的钥匙串里。")
            }
            Section {
                Toggle("推送通知（APNs）", isOn: $pushEnabled)
                if let status = store.pushStatus { Text(status).font(.callout).foregroundStyle(.secondary) }
            } header: {
                Text("提醒（默认关闭）")
            } footer: {
                Text("打开后，Mac mini 的主机告警和量化告警经苹果推送到这台 Mac，和 iPhone 各收各的；Mac mini 上也要打开 APNs 开关。推送只写告警类型和时间，点开会显示这条告警的详情和同类历史。PortSight 关着时也能收到。")
            }
        }
        .onAppear { if url.isEmpty { url = store.baseURL } }
        .onChange(of: pushEnabled) { _, on in
            Task {
                if on {
                    if !(await DesktopServerPush.enable()) {
                        pushEnabled = false
                        store.pushStatus = "通知权限被拒绝：到 系统设置 → 通知 → PortsightMac 打开"
                    }
                } else {
                    await DesktopServerPush.disable()
                }
            }
        }
    }
}

/// 未配对 / 已配对 / 令牌已交给服务器 / 需要重新配对
struct DesktopPairingStateLabel: View {
    let state: RelayPairingState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(state.title)
        }
        .foregroundStyle(color)
    }

    private var icon: String {
        switch state {
        case .unpaired: "link"
        case .paired: "checkmark.circle.fill"
        case .pushDelivered: "bell.badge.fill"
        case .needsRepair: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .unpaired: .secondary
        case .paired, .pushDelivered: DesktopTheme.green
        case .needsRepair: DesktopTheme.orange
        }
    }
}
