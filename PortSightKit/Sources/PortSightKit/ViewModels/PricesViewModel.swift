//
//  PricesViewModel.swift
//  PortSight
//
//  Created by Chris Cui on 4/5/2026.
//
import Combine
import Foundation

@MainActor
public final class PricesViewModel: ObservableObject {
    @Published public var prices: [String: Double] = [:]   // instId -> price
    @Published public var errorText: String? = nil
    
    private let cacheKey = "okx_prices_cache"

    private let service = OKXMarketService()
    private var task: Task<Void, Never>?
    
    public init() {
        loadCache()
    }
    
    private func loadCache() {
        // Built-in crypto prices before pairing; none once paired (the relay has no crypto prices).
        // Built-in crypto prices, paired or not (the relay has no crypto prices).
        if DemoPortfolioData.enabled { prices = ["BTC-USDT": 70000, "ETH-USDT": 3000]; return }
        if let cached = CacheManager.load([String: Double].self, key: cacheKey) {
            prices = cached
        }
    }

    public func start(instIds: [String], every seconds: Double = 3.0) {
        if DemoPortfolioData.enabled { loadCache(); return }
        task?.cancel()
        loadCache()

        task = Task {
            while !Task.isCancelled {
                do {
                    try await fetchAll(instIds: instIds)
                    CacheManager.save(prices, key: cacheKey)
                    errorText = nil
                } catch {
                    errorText = error.localizedDescription
                    print("OKX balance error:", error.localizedDescription)
                    loadCache()
                }

                try? await Task.sleep(
                    nanoseconds: UInt64(seconds * 1_000_000_000)
                )
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func fetchAll(instIds: [String]) async throws {
        try await withThrowingTaskGroup(of: OKXIndexTicker.self) { group in
            for id in instIds {
                group.addTask { try await self.service.fetchIndexTicker(instId: id) }
            }

            for try await t in group {
                if let p = Double(t.idxPx) {
                    prices[t.instId] = p
                }
            }
        }
    }

    public func price(for instId: String) -> Double? {
        prices[instId]
    }
}
