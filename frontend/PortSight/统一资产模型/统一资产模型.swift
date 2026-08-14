//
//  AssetType.swift
//  PortSight
//
//  Created by Chris Cui on 4/5/2026.
//
import Combine
import Foundation

enum AssetType: String, Codable {
    case stock
    case crypto
    case cash
}

struct PortfolioAsset: Identifiable, Codable {
    var id: String { "\(source)-\(type.rawValue)-\(symbol)" }

    let type: AssetType
    let symbol: String
    let name: String
    let quantity: Double
    let avgCost: Double
    let currentPrice: Double      // 最新价（统一后的）
    let prevClosePrice: Double    // 昨收价（必须有）
    let marketValue: Double
    let realizedPnL: Double
    let unrealizedPnL: Double
    let pnlRatio: Double
    let currency: String
    let source: String
}

extension Position {
    var asPortfolioAsset: PortfolioAsset {
        PortfolioAsset(
            type: .stock,
            symbol: displaySymbol,
            name: name,
            quantity: quantity,
            avgCost: avgCost,
            currentPrice: currentPrice,
            prevClosePrice: currentPrice, // 先用 currentPrice 兜底
            marketValue: marketValue,
            realizedPnL: realizedPnL,
            unrealizedPnL: unrealizedPnL,
            pnlRatio: pnlPercent,
            currency: "USD",
            source: "moomoo"
        )
    }
}

extension OKXBalanceDetail {
    var quantity: Double {
        Double(spotBal ?? "") ?? 0
    }

    var avgCost: Double {
        Double(accAvgPx ?? "") ?? 0
    }

    var marketValue: Double {
        Double(eqUsd ?? "") ?? 0
    }

    var currentPrice: Double {
        quantity > 0 ? marketValue / quantity : 0
    }

    var unrealizedPnL: Double {
        Double(spotUpl ?? "") ?? 0
    }

    var unrealizedPnLRatio: Double {
        Double(spotUplRatio ?? "") ?? 0
    }

    var totalPnLValue: Double {
        Double(totalPnl ?? "") ?? 0
    }

    var totalPnLRatioValue: Double {
        Double(totalPnlRatio ?? "") ?? 0
    }
    
    var instId: String {
        "\(ccy.uppercased())-USDT"
    }

    var asPortfolioAsset: PortfolioAsset {
        PortfolioAsset(
            type: .crypto,
            symbol: ccy.uppercased(),
            name: ccy.uppercased(),
            quantity: quantity,
            avgCost: avgCost,
            currentPrice: currentPrice,
            prevClosePrice: currentPrice,
            marketValue: marketValue,
            realizedPnL: 0,
            unrealizedPnL: unrealizedPnL,
            pnlRatio: unrealizedPnLRatio,
            currency: "USD",
            source: "okx"
        )
    }
}
