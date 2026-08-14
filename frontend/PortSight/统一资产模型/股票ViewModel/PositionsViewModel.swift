//
//  PositionsViewModel.swift
//  PortSight
//
//  Created by Chris Cui on 30/4/2026.
//

import Foundation
import Combine
import SwiftUI

struct Position: Codable, Identifiable {
    var id: String { symbol }

    let symbol: String
    let name: String
    let quantity: Double
    let avgCost: Double
    let marketValue: Double
    let pnl: Double
    let pnlPercent: Double
    let realizedPnL: Double
    let unrealizedPnL: Double
    let isEtf: Bool
    let assetClass: String?
    var safeAvgCost: Double {
        avgCost > 0 ? avgCost : 0
    }
    var pnlColor: Color {
        pnl >= 0 ? .green : .red
    }
    var displaySymbol: String {
        symbol.split(separator: ".").last.map(String.init) ?? symbol
    }
    var currentPrice: Double {
        quantity > 0 ? marketValue / quantity : 0
    }
}
extension Position {
    enum CodingKeys: String, CodingKey {
        case symbol = "code"
        case name
        case quantity = "qty"
        case avgCost = "cost_price"
        case marketValue = "market_val"
        case pnl = "pl_val"
        case pnlPercent = "pl_ratio"
        case realizedPnL = "realized_pl"
        case unrealizedPnL = "unrealized_pl"
        case isEtf = "is_etf"
        case assetClass = "asset_class"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        symbol = try container.decode(String.self, forKey: .symbol)
        name = try container.decode(String.self, forKey: .name)
        quantity = try container.decode(Double.self, forKey: .quantity)
        avgCost = try container.decode(Double.self, forKey: .avgCost)
        marketValue = try container.decode(Double.self, forKey: .marketValue)
        pnl = try container.decode(Double.self, forKey: .pnl)
        pnlPercent = try container.decode(Double.self, forKey: .pnlPercent)
        realizedPnL = try container.decode(Double.self, forKey: .realizedPnL)
        unrealizedPnL = try container.decode(Double.self, forKey: .unrealizedPnL)
        let decodedAssetClass = try container.decodeIfPresent(String.self, forKey: .assetClass)
        let assetClassIsEtf = decodedAssetClass?.uppercased() == "ETF"
        assetClass = decodedAssetClass
        isEtf = (try container.decodeIfPresent(Bool.self, forKey: .isEtf)) ?? assetClassIsEtf
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(symbol, forKey: .symbol)
        try container.encode(name, forKey: .name)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(avgCost, forKey: .avgCost)
        try container.encode(marketValue, forKey: .marketValue)
        try container.encode(pnl, forKey: .pnl)
        try container.encode(pnlPercent, forKey: .pnlPercent)
        try container.encode(realizedPnL, forKey: .realizedPnL)
        try container.encode(unrealizedPnL, forKey: .unrealizedPnL)
        try container.encode(isEtf, forKey: .isEtf)
        try container.encodeIfPresent(assetClass, forKey: .assetClass)
    }
}

struct PositionsResponse: Codable {
    let ok: Bool
    let positions: [Position]
}

@MainActor
class PositionsViewModel: ObservableObject {
    @Published var positions: [Position] = []
    private var refreshTask: Task<Void, Never>?

    private let cacheKey = "positions_cache_v2"

    init() {
        loadCache()
    }

    func loadCache() {
        if let cached = CacheManager.load([Position].self, key: cacheKey) {
            self.positions = cached
        }
    }

    func fetchPositions() async {
        do {
            let sortedPositions = try await fetchServerPositions()
            applyPositions(sortedPositions)
            await CacheManager.saveAsync(sortedPositions, key: cacheKey)
        } catch {
            print("fetch positions error:", error)
        }
    }

    func fetchServerPositions() async throws -> [Position] {
        guard let url = BackendConfig.url(path: "positions") else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let result = try await CacheManager.decode(PositionsResponse.self, from: data)

        guard result.ok else {
            throw URLError(.badServerResponse)
        }

        return await Task.detached(priority: .utility) {
            result.positions.sorted { $0.marketValue > $1.marketValue }
        }.value
    }

    func applyPositions(_ newPositions: [Position]) {
        guard positionsSignature(positions) != positionsSignature(newPositions) else { return }
        positions = newPositions
    }

    private func positionsSignature(_ positions: [Position]) -> String {
        positions
            .map { "\($0.symbol):\($0.quantity):\($0.marketValue):\($0.pnl):\($0.avgCost)" }
            .joined(separator: "|")
    }
    
    func startAutoRefresh(immediately: Bool = true) {
        if refreshTask != nil { return }
        refreshTask = Task {
            if immediately {
                await fetchPositions()
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                await fetchPositions()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
