//
//  AssetType.swift
//  PortSight
//
//  Created by Chris Cui on 4/5/2026.
//
import Combine
import Foundation

public enum AssetType: String, Codable {
    case stock
    case crypto
    case cash
}

public struct PortfolioAsset: Identifiable, Codable {
    public var id: String { "\(source)-\(type.rawValue)-\(symbol)" }

    public let type: AssetType
    public let symbol: String
    public let name: String
    public let quantity: Double
    public let avgCost: Double
    public let currentPrice: Double      // 最新价（统一后的）
    public let prevClosePrice: Double    // 昨收价（必须有）
    public let marketValue: Double
    public let realizedPnL: Double
    public let unrealizedPnL: Double
    public let pnlRatio: Double
    public let currency: String
    public let source: String

    public init(type: AssetType, symbol: String, name: String, quantity: Double, avgCost: Double, currentPrice: Double, prevClosePrice: Double, marketValue: Double, realizedPnL: Double, unrealizedPnL: Double, pnlRatio: Double, currency: String, source: String) {
        self.type = type
        self.symbol = symbol
        self.name = name
        self.quantity = quantity
        self.avgCost = avgCost
        self.currentPrice = currentPrice
        self.prevClosePrice = prevClosePrice
        self.marketValue = marketValue
        self.realizedPnL = realizedPnL
        self.unrealizedPnL = unrealizedPnL
        self.pnlRatio = pnlRatio
        self.currency = currency
        self.source = source
    }
}

extension Position {
    public var asPortfolioAsset: PortfolioAsset {
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
    public var quantity: Double {
        Double(spotBal ?? "") ?? 0
    }

    public var avgCost: Double {
        Double(accAvgPx ?? "") ?? 0
    }

    public var marketValue: Double {
        Double(eqUsd ?? "") ?? 0
    }

    public var currentPrice: Double {
        quantity > 0 ? marketValue / quantity : 0
    }

    public var unrealizedPnL: Double {
        Double(spotUpl ?? "") ?? 0
    }

    public var unrealizedPnLRatio: Double {
        Double(spotUplRatio ?? "") ?? 0
    }

    public var totalPnLValue: Double {
        Double(totalPnl ?? "") ?? 0
    }

    public var totalPnLRatioValue: Double {
        Double(totalPnlRatio ?? "") ?? 0
    }
    
    public var instId: String {
        "\(ccy.uppercased())-USDT"
    }

    public var asPortfolioAsset: PortfolioAsset {
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
