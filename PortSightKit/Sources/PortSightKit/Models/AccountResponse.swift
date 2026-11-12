//
//  AccountResponse.swift
//  PortSight
//
//  Created by Chris Cui on 30/4/2026.
//
import SwiftUI
import Combine
import Foundation

public struct AccountResponse: Codable {
    public let ok: Bool
    public let total_assets: Double?
    public let principal: [String: Double]?
    public let principal_total: Double?
    public let buying_power: Double?
    public let cash: Double?
    public let market_value: Double?
    public let currency: String?
    public let error: String?

    public init(ok: Bool, total_assets: Double?, principal: [String: Double]?, principal_total: Double?, buying_power: Double?, cash: Double?, market_value: Double?, currency: String?, error: String?) {
        self.ok = ok
        self.total_assets = total_assets
        self.principal = principal
        self.principal_total = principal_total
        self.buying_power = buying_power
        self.cash = cash
        self.market_value = market_value
        self.currency = currency
        self.error = error
    }
}


@MainActor
public class MoomooAccountViewModel: ObservableObject {
    @Published public var totalAssets: Double = 0
    @Published public var buyingPower: Double = 0
    @Published public var principalTotal: Double = 0
    @Published public var currency: String = "USD"

    @Published public var connectionStatus: String = "未连接"
    @Published public var isConnected: Bool = false
    @Published public var errorMessage: String?

    public func fetchAccount() async {
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

    public init() {}
}
