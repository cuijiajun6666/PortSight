import SwiftUI
import PortSightKit

/// 设置. The Mac mini is reached only through 服务器 (pairing with the relay); there is no separate backend address.
/// Native controls: the sheet container gives its pages glass buttons, so this form puts back the system style.
struct DesktopSettingsView: View {
    @AppStorage("desktop_appearance") private var appearance = "system"
    @ObservedObject private var server = ServerStore.shared
    var body: some View {
        Form {
            Section("外观") {
                Picker("主题", selection: $appearance) {
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                    Text("跟随系统").tag("system")
                }
                .pickerStyle(.segmented)
            }
            Section("数据模式") {
                LabeledContent("当前模式", value: server.isPaired ? "离线（服务器已配对）" : "离线 (未接入服务器)")
                LabeledContent("显示币种", value: "USD")
                LabeledContent("数据", value: "与 iOS 相同")
                Text("除了服务器配对，这里的设置不会发起网络请求。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            DesktopServerPairingSections()
            Section("预留连接") {
                LabeledContent("moomoo", value: "尚未连接")
                LabeledContent("OKX", value: "尚未连接")
            }
            Section("PortSight for Mac") {
                LabeledContent("版本", value: "1.0 · Desktop Preview")
                Text("你的资产、持仓与量化策略，一处看见。")
            }
        }
        .formStyle(.grouped)
        .buttonStyle(.automatic)
    }
}
