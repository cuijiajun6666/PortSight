//
//  设置？.swift
//  PortSight
//
//  Created by Chris Cui on 30/4/2026.
//
//  通用设置. The Mac mini is reached only through 量化服务器 (pairing with the relay); there is no separate
//  backend address any more. Native controls and colours throughout: no tint override.
//

import SwiftUI
import PortSightKit

struct 名字待定2: View {
    @ObservedObject private var server = ServerStore.shared
    @State private var digestHour = 21
    @State private var showAmounts = true
    @State private var noticeSound = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("通知预览") {
                    Toggle("通知声音", isOn: $noticeSound)
                    Toggle("显示通知金额", isOn: $showAmounts)
                    Stepper("每日摘要：\(digestHour):00 悉尼时间", value: $digestHour, in: 0...23)
                    Text("这些选项只用于预览设置界面。").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    NavigationLink {
                        ServerPairingForm().navigationTitle("配对与推送")
                    } label: {
                        LabeledContent("配对与推送") { ServerPairingStateLabel(state: server.pairingState) }
                    }
                } header: {
                    Text("量化服务器")
                } footer: {
                    Text("家里的 Mac mini：主机状态、告警和推送都从这里连。")
                }
                Section {
                    NavigationLink("OKX 只读密钥") { OKXCredentialsView() }
                } footer: {
                    Text("密钥存在这台手机的钥匙串里，不写进代码。")
                }
            }
            .navigationTitle("设置")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}
