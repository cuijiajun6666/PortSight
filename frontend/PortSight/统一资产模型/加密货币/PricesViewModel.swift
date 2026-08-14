//
//  PricesViewModel.swift
//  PortSight
//
//  Created by Chris Cui on 4/5/2026.
//
import Combine
import Foundation

@MainActor
final class PricesViewModel: ObservableObject {
    @Published var prices: [String: Double] = [:]   // instId -> price
    @Published var errorText: String? = nil
    
    private let cacheKey = "okx_prices_cache"

    private let service = OKXMarketService()
    private var task: Task<Void, Never>?
    
    init() {
        loadCache()
    }
    
    private func loadCache() {
        if let cached = CacheManager.load([String: Double].self, key: cacheKey) {
            prices = cached
        }
    }

    func start(instIds: [String], every seconds: Double = 3.0) {
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

    func stop() {
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

    func price(for instId: String) -> Double? {
        prices[instId]
    }
}
