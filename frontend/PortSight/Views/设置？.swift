//
//  设置？.swift
//  PortSight
//
//  Created by Chris Cui on 30/4/2026.
//

import SwiftUI

struct 名字待定2: View {
    @AppStorage(BackendConfig.storageKey) private var savedBaseURL = ""
    @State private var serverAddress: String
    @State private var connectionStatus = ""
    @State private var isTestingConnection = false

    init() {
        _serverAddress = State(initialValue: BackendConfig.baseURLString)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(BackendConfig.defaultBaseURL, text: $serverAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    HStack {
                        Button("保存地址") {
                            saveServerAddress()
                        }

                        Spacer()

                        Button {
                            Task {
                                await testConnection()
                            }
                        } label: {
                            if isTestingConnection {
                                ProgressView()
                            } else {
                                Text("测试连接")
                            }
                        }
                        .disabled(isTestingConnection)
                    }
                } header: {
                    Text("后端服务器")
                } footer: {
                    Text("当前连接地址：\(BackendConfig.baseURLString)")
                }

                if !connectionStatus.isEmpty {
                    Section {
                        Text(connectionStatus)
                            .foregroundStyle(connectionStatus == "连接成功" ? .green : .secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .onChange(of: savedBaseURL) { _, _ in
                serverAddress = BackendConfig.baseURLString
            }
        }
    }

    private func saveServerAddress() {
        BackendConfig.save(serverAddress)
        savedBaseURL = BackendConfig.baseURLString
        serverAddress = BackendConfig.baseURLString
        connectionStatus = "已保存"
    }

    private func testConnection() async {
        saveServerAddress()
        isTestingConnection = true
        defer { isTestingConnection = false }

        guard let url = BackendConfig.url(path: "account") else {
            connectionStatus = "地址格式不正确"
            return
        }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                connectionStatus = "服务器没有返回有效响应"
                return
            }

            connectionStatus = (200..<300).contains(httpResponse.statusCode)
                ? "连接成功"
                : "连接失败：HTTP \(httpResponse.statusCode)"
        } catch {
            connectionStatus = "连接失败：\(error.localizedDescription)"
        }
    }
}
