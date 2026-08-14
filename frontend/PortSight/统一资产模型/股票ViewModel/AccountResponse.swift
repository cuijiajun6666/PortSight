//
//  AccountResponse.swift
//  PortSight
//
//  Created by Chris Cui on 30/4/2026.
//
import SwiftUI
import Combine
import Foundation

struct AccountResponse: Codable {
    let ok: Bool
    let total_assets: Double?
    let principal: [String: Double]?
    let principal_total: Double?
    let buying_power: Double?
    let cash: Double?
    let market_value: Double?
    let currency: String?
    let error: String?
}


@MainActor
class MoomooAccountViewModel: ObservableObject {
    @Published var totalAssets: Double = 0
    @Published var buyingPower: Double = 0
    @Published var principalTotal: Double = 0
    @Published var currency: String = "USD"

    @Published var connectionStatus: String = "未连接"
    @Published var isConnected: Bool = false
    @Published var errorMessage: String?

    func fetchAccount() async {
        connectionStatus = "连接中..."
        errorMessage = nil

        guard let url = BackendConfig.url(path: "account") else {
            connectionStatus = "地址错误"
            isConnected = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try JSONDecoder().decode(AccountResponse.self, from: data)

            if result.ok {
                totalAssets = result.total_assets ?? 0
                buyingPower = result.buying_power ?? 0
                principalTotal = result.principal_total ?? 0
                currency = result.currency ?? "USD"

                connectionStatus = "已连接"
                isConnected = true
            } else {
                connectionStatus = "连接失败"
                isConnected = false
                errorMessage = result.error
            }

        } catch {
            connectionStatus = "连接失败"
            isConnected = false
            errorMessage = error.localizedDescription
        }
    }
}
