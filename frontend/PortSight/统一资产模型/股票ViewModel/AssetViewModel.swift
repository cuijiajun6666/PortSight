//
//  AssetViewModel.swift
//  PortSight
//
//  Created by Chris Cui on 30/4/2026.
//
import Combine
import Foundation

@MainActor
class AssetViewModel: ObservableObject {
    @Published var totalAsset: Double = 0
    @Published var buyingPower: Double = 0
    @Published var principalTotal: Double = 0
    @Published var currency: String = "USD"
    @Published var isConnected: Bool = false
    @Published var connectionStatus: String = "未连接"
    @Published var errorMessage: String?
    private var refreshTask: Task<Void, Never>?

    private let cacheKey = "account_cache"

    init() {
        loadCache()
    }

    func loadCache() {
        if let cached = CacheManager.load(AccountResponse.self, key: cacheKey) {
            totalAsset = cached.total_assets ?? 0
            buyingPower = cached.buying_power ?? 0
            principalTotal = cached.principal_total ?? 0
            currency = cached.currency ?? "USD"
            connectionStatus = "已加载缓存"
            isConnected = false
        }
    }

    func fetchAccount(showLoading: Bool = true) async {
        if showLoading {
            connectionStatus = "连接中..."
        }

        errorMessage = nil

        guard let url = BackendConfig.url(path: "account") else {
            connectionStatus = "URL错误"
            isConnected = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try await CacheManager.decode(AccountResponse.self, from: data)

            if result.ok {
                totalAsset = result.total_assets ?? 0
                buyingPower = result.buying_power ?? 0
                principalTotal = result.principal_total ?? 0
                currency = result.currency ?? "USD"
                isConnected = true
                connectionStatus = "已连接"

                await CacheManager.saveAsync(result, key: cacheKey)
            } else {
                isConnected = false
                connectionStatus = "连接失败"
                errorMessage = result.error
            }
        } catch {
            isConnected = false
            connectionStatus = "连接失败"
            errorMessage = error.localizedDescription
        }
    }
    
    func startAutoRefresh(immediately: Bool = true) {
        if refreshTask != nil { return }   // 已经在刷新就不要重复启动
        refreshTask = Task {
            if immediately {
                await fetchAccount(showLoading: false)
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                await fetchAccount(showLoading: false)
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
