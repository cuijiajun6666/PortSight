//
//  OKXCredentials.swift
//  PortSight
//
//  OKX API key, secret and passphrase in this phone's Keychain (they used to be written into DashboardView).
//  Entered once in Settings → OKX 只读密钥; never shown again, never logged. Use a read-only key without
//  withdrawal or trading permission.
//

import SwiftUI
import PortSightKit

struct OKXCredentialsView: View {
    @State private var apiKey = ""
    @State private var secretKey = ""
    @State private var passphrase = ""
    @State private var saved = OKXCredentials.load() != nil
    @State private var note: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("状态", value: saved ? "已保存在钥匙串" : "未设置")
            } footer: {
                Text("只用只读权限的密钥：不要勾选提现和交易。保存后不再显示；更换时直接重新填写。改完要重新打开 App 才生效。")
            }
            Section("新密钥") {
                SecureField("API Key", text: $apiKey)
                SecureField("Secret Key", text: $secretKey)
                SecureField("Passphrase", text: $passphrase)
                Button("保存") {
                    let c = OKXCredentials(apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                           secretKey: secretKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                           passphrase: passphrase.trimmingCharacters(in: .whitespacesAndNewlines))
                    if c.save() {
                        saved = true; note = "已保存"
                        apiKey = ""; secretKey = ""; passphrase = ""
                    } else {
                        note = "保存失败"
                    }
                }
                .disabled(apiKey.isEmpty || secretKey.isEmpty || passphrase.isEmpty)
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            if saved {
                Section {
                    Button("删除已保存的密钥", role: .destructive) { OKXCredentials.clear(); saved = false; note = "已删除" }
                }
            }
        }
        .navigationTitle("OKX 只读密钥")
    }
}
