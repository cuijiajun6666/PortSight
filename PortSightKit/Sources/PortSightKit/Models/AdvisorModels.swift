//
//  AdvisorViewModel.swift
//  PortSight
//
//  Created by Codex on 26/5/2026.
//

import Combine
import Foundation

public struct AdvisorSummaryResponse: Codable {
    public let ok: Bool
    public let updatedAt: String?
    public let portfolio: AdvisorPortfolio?
    public let positions: [AdvisorPosition]
    public let alerts: [AdvisorAlert]
    public let error: String?

    public enum CodingKeys: String, CodingKey {
        case ok
        case updatedAt = "updated_at"
        case portfolio
        case positions
        case alerts
        case error
    }

    public init(ok: Bool, updatedAt: String?, portfolio: AdvisorPortfolio?, positions: [AdvisorPosition], alerts: [AdvisorAlert], error: String?) {
        self.ok = ok
        self.updatedAt = updatedAt
        self.portfolio = portfolio
        self.positions = positions
        self.alerts = alerts
        self.error = error
    }
}

public struct AdvisorPortfolio: Codable {
    public let marketValue: Double?
    public let riskScore: Double?
    public let score: Double?
    public let rating: String?
    public let ratingLabel: String?
    public let ratingDescription: String?
    public let scoreRanges: [AdvisorScoreRange]?
    public let pnl: AdvisorPnL?
    public let suggestion: String?
    public let reasons: [String]?
    public let sectorExposure: [String: Double]?
    public let correlation: AdvisorCorrelation?

    public enum CodingKeys: String, CodingKey {
        case marketValue = "market_value"
        case riskScore = "risk_score"
        case score
        case rating
        case ratingLabel = "rating_label"
        case ratingDescription = "rating_description"
        case scoreRanges = "score_ranges"
        case pnl
        case suggestion
        case reasons
        case sectorExposure = "sector_exposure"
        case correlation
    }

    public init(marketValue: Double?, riskScore: Double?, score: Double?, rating: String?, ratingLabel: String?, ratingDescription: String?, scoreRanges: [AdvisorScoreRange]?, pnl: AdvisorPnL?, suggestion: String?, reasons: [String]?, sectorExposure: [String: Double]?, correlation: AdvisorCorrelation?) {
        self.marketValue = marketValue
        self.riskScore = riskScore
        self.score = score
        self.rating = rating
        self.ratingLabel = ratingLabel
        self.ratingDescription = ratingDescription
        self.scoreRanges = scoreRanges
        self.pnl = pnl
        self.suggestion = suggestion
        self.reasons = reasons
        self.sectorExposure = sectorExposure
        self.correlation = correlation
    }
}

public struct AdvisorScoreRange: Codable {
    public let min: Double
    public let max: Double
    public let rating: String
    public let label: String

    public init(min: Double, max: Double, rating: String, label: String) {
        self.min = min
        self.max = max
        self.rating = rating
        self.label = label
    }
}

public struct AdvisorPnL: Codable {
    public let unrealizedPL: Double?
    public let realizedPL: Double?
    public let totalPL: Double?
    public let plRatio: Double?

    public enum CodingKeys: String, CodingKey {
        case unrealizedPL = "unrealized_pl"
        case realizedPL = "realized_pl"
        case totalPL = "total_pl"
        case plRatio = "pl_ratio"
    }

    public init(unrealizedPL: Double?, realizedPL: Double?, totalPL: Double?, plRatio: Double?) {
        self.unrealizedPL = unrealizedPL
        self.realizedPL = realizedPL
        self.totalPL = totalPL
        self.plRatio = plRatio
    }
}

public struct AdvisorCorrelation: Codable {
    public let pairs: [AdvisorCorrelationPair]?

    public init(pairs: [AdvisorCorrelationPair]?) {
        self.pairs = pairs
    }
}

public struct AdvisorCorrelationPair: Codable, Identifiable {
    public var id: String { "\(left)-\(right)" }

    public let left: String
    public let right: String
    public let correlation: Double

    public init(left: String, right: String, correlation: Double) {
        self.left = left
        self.right = right
        self.correlation = correlation
    }
}

public struct AdvisorPosition: Codable, Identifiable {
    public var id: String { code }

    public let code: String
    public let name: String?
    public let sector: String?
    public let weight: Double?
    public let qty: Double?
    public let costPrice: Double?
    public let marketValue: Double?
    public let close: Double?
    public let realizedPL: Double?
    public let unrealizedPL: Double?
    public let plRatio: Double?
    public let riskScore: Double?
    public let technicalScore: Double?
    public let confirmed: Bool?
    public let action: String?
    public let suggestion: String?
    public let reasons: [String]?
    public let tradePlan: AdvisorTradePlan?
    public let prediction: AdvisorPrediction?
    public let signals: AdvisorSignals?
    public let profile: AdvisorProfile?
    public let priceStructure: AdvisorPriceStructure?
    public let analysisPoints: [AdvisorAnalysisPoint]?
    public let scoreBreakdown: AdvisorScoreBreakdown?

    public enum CodingKeys: String, CodingKey {
        case code
        case name
        case sector
        case weight
        case qty
        case costPrice = "cost_price"
        case marketValue = "market_val"
        case close
        case realizedPL = "realized_pl"
        case unrealizedPL = "unrealized_pl"
        case plRatio = "pl_ratio"
        case riskScore = "risk_score"
        case technicalScore = "technical_score"
        case confirmed
        case action
        case suggestion
        case reasons
        case tradePlan = "trade_plan"
        case prediction
        case signals
        case profile
        case priceStructure = "price_structure"
        case analysisPoints = "analysis_points"
        case scoreBreakdown = "score_breakdown"
    }

    public init(code: String, name: String?, sector: String?, weight: Double?, qty: Double?, costPrice: Double?, marketValue: Double?, close: Double?, realizedPL: Double?, unrealizedPL: Double?, plRatio: Double?, riskScore: Double?, technicalScore: Double?, confirmed: Bool?, action: String?, suggestion: String?, reasons: [String]?, tradePlan: AdvisorTradePlan?, prediction: AdvisorPrediction?, signals: AdvisorSignals?, profile: AdvisorProfile?, priceStructure: AdvisorPriceStructure?, analysisPoints: [AdvisorAnalysisPoint]?, scoreBreakdown: AdvisorScoreBreakdown?) {
        self.code = code
        self.name = name
        self.sector = sector
        self.weight = weight
        self.qty = qty
        self.costPrice = costPrice
        self.marketValue = marketValue
        self.close = close
        self.realizedPL = realizedPL
        self.unrealizedPL = unrealizedPL
        self.plRatio = plRatio
        self.riskScore = riskScore
        self.technicalScore = technicalScore
        self.confirmed = confirmed
        self.action = action
        self.suggestion = suggestion
        self.reasons = reasons
        self.tradePlan = tradePlan
        self.prediction = prediction
        self.signals = signals
        self.profile = profile
        self.priceStructure = priceStructure
        self.analysisPoints = analysisPoints
        self.scoreBreakdown = scoreBreakdown
    }
}

public struct AdvisorTradePlan: Codable {
    public let alertType: String?
    public let buyPercent: Double?
    public let sellPercent: Double?
    public let sellQty: Double?
    public let triggerPrice: Double?
    public let triggerCondition: String?
    public let basis: String?

    public enum CodingKeys: String, CodingKey {
        case alertType = "alert_type"
        case buyPercent = "buy_percent"
        case sellPercent = "sell_percent"
        case sellQty = "sell_qty"
        case triggerPrice = "trigger_price"
        case triggerCondition = "trigger_condition"
        case basis
    }

    public init(alertType: String?, buyPercent: Double?, sellPercent: Double?, sellQty: Double?, triggerPrice: Double?, triggerCondition: String?, basis: String?) {
        self.alertType = alertType
        self.buyPercent = buyPercent
        self.sellPercent = sellPercent
        self.sellQty = sellQty
        self.triggerPrice = triggerPrice
        self.triggerCondition = triggerCondition
        self.basis = basis
    }
}

public struct AdvisorPrediction: Codable {
    public let expectedVolatility30d: Double?
    public let trend5d: Double?
    public let trend20d: Double?
    public let trend60d: Double?
    public let drawdownFromHigh: Double?
    public let expectedByHorizon: [String: AdvisorHorizonExpectation]?

    public enum CodingKeys: String, CodingKey {
        case expectedVolatility30d = "expected_volatility_30d"
        case trend5d = "trend_5d"
        case trend20d = "trend_20d"
        case trend60d = "trend_60d"
        case drawdownFromHigh = "drawdown_from_high"
        case expectedByHorizon = "expected_by_horizon"
    }

    public init(expectedVolatility30d: Double?, trend5d: Double?, trend20d: Double?, trend60d: Double?, drawdownFromHigh: Double?, expectedByHorizon: [String: AdvisorHorizonExpectation]?) {
        self.expectedVolatility30d = expectedVolatility30d
        self.trend5d = trend5d
        self.trend20d = trend20d
        self.trend60d = trend60d
        self.drawdownFromHigh = drawdownFromHigh
        self.expectedByHorizon = expectedByHorizon
    }
}

public struct AdvisorHorizonExpectation: Codable {
    public let expectedReturn: Double?
    public let expectedVolatility: Double?
    public let expectedMaxDrawdown: Double?

    public enum CodingKeys: String, CodingKey {
        case expectedReturn = "expected_return"
        case expectedVolatility = "expected_volatility"
        case expectedMaxDrawdown = "expected_max_drawdown"
    }

    public init(expectedReturn: Double?, expectedVolatility: Double?, expectedMaxDrawdown: Double?) {
        self.expectedReturn = expectedReturn
        self.expectedVolatility = expectedVolatility
        self.expectedMaxDrawdown = expectedMaxDrawdown
    }
}

public struct AdvisorSignals: Codable {
    public let daily: AdvisorDailySignals?
    public let weekly: AdvisorWeeklySignals?
    public let monthly: AdvisorMonthlySignals?

    public init(daily: AdvisorDailySignals?, weekly: AdvisorWeeklySignals?, monthly: AdvisorMonthlySignals?) {
        self.daily = daily
        self.weekly = weekly
        self.monthly = monthly
    }
}

public struct AdvisorDailySignals: Codable {
    public let ma20: Double?
    public let ma60: Double?
    public let rsi14: Double?
    public let volatility60d: Double?
    public let volatilityTier: String?

    public enum CodingKeys: String, CodingKey {
        case ma20
        case ma60
        case rsi14
        case volatility60d = "volatility_60d"
        case volatilityTier = "volatility_tier"
    }

    public init(ma20: Double?, ma60: Double?, rsi14: Double?, volatility60d: Double?, volatilityTier: String?) {
        self.ma20 = ma20
        self.ma60 = ma60
        self.rsi14 = rsi14
        self.volatility60d = volatility60d
        self.volatilityTier = volatilityTier
    }
}

public struct AdvisorWeeklySignals: Codable {
    public let bollPosition: Double?
    public let close: Double?

    public enum CodingKeys: String, CodingKey {
        case bollPosition = "boll_position"
        case close
    }

    public init(bollPosition: Double?, close: Double?) {
        self.bollPosition = bollPosition
        self.close = close
    }
}

public struct AdvisorMonthlySignals: Codable {
    public let close: Double?
    public let ma20: Double?

    public init(close: Double?, ma20: Double?) {
        self.close = close
        self.ma20 = ma20
    }
}

public struct AdvisorProfile: Codable {
    public let riskTier: String?
    public let sizeTier: String?
    public let volatilityTier: String?
    public let personality: AdvisorPersonality?

    public enum CodingKeys: String, CodingKey {
        case riskTier = "risk_tier"
        case sizeTier = "size_tier"
        case volatilityTier = "volatility_tier"
        case personality
    }

    public init(riskTier: String?, sizeTier: String?, volatilityTier: String?, personality: AdvisorPersonality?) {
        self.riskTier = riskTier
        self.sizeTier = sizeTier
        self.volatilityTier = volatilityTier
        self.personality = personality
    }
}

public struct AdvisorPersonality: Codable {
    public let type: String?
    public let traits: [String]?
    public let rsiHotThreshold: Double?
    public let maxBuyPercent: Double?
    public let strategyNote: String?

    public enum CodingKeys: String, CodingKey {
        case type
        case traits
        case rsiHotThreshold = "rsi_hot_threshold"
        case maxBuyPercent = "max_buy_percent"
        case strategyNote = "strategy_note"
    }

    public init(type: String?, traits: [String]?, rsiHotThreshold: Double?, maxBuyPercent: Double?, strategyNote: String?) {
        self.type = type
        self.traits = traits
        self.rsiHotThreshold = rsiHotThreshold
        self.maxBuyPercent = maxBuyPercent
        self.strategyNote = strategyNote
    }
}

public struct AdvisorPriceStructure: Codable {
    public let status: String?
    public let score: Double?
    public let points: [String]?
    public let recentHigh20: Double?
    public let recentLow20: Double?
    public let volumeExpansion: Bool?

    public enum CodingKeys: String, CodingKey {
        case status
        case score
        case points
        case recentHigh20 = "recent_high_20"
        case recentLow20 = "recent_low_20"
        case volumeExpansion = "volume_expansion"
    }

    public init(status: String?, score: Double?, points: [String]?, recentHigh20: Double?, recentLow20: Double?, volumeExpansion: Bool?) {
        self.status = status
        self.score = score
        self.points = points
        self.recentHigh20 = recentHigh20
        self.recentLow20 = recentLow20
        self.volumeExpansion = volumeExpansion
    }
}

public struct AdvisorAnalysisPoint: Codable, Identifiable {
    public var id: String { "\(category ?? "")-\(label ?? "")-\(detail ?? "")" }

    public let category: String?
    public let label: String?
    public let status: String?
    public let detail: String?

    public init(category: String?, label: String?, status: String?, detail: String?) {
        self.category = category
        self.label = label
        self.status = status
        self.detail = detail
    }
}

public struct AdvisorScoreBreakdown: Codable {
    public let trendScore: Double?
    public let momentumScore: Double?
    public let volatilityRisk: Double?
    public let capitalAddon: Double?
    public let shortAddon: Double?
    public let insiderAddon: Double?

    public enum CodingKeys: String, CodingKey {
        case trendScore = "trend_score"
        case momentumScore = "momentum_score"
        case volatilityRisk = "volatility_risk"
        case capitalAddon = "capital_addon"
        case shortAddon = "short_addon"
        case insiderAddon = "insider_addon"
    }

    public init(trendScore: Double?, momentumScore: Double?, volatilityRisk: Double?, capitalAddon: Double?, shortAddon: Double?, insiderAddon: Double?) {
        self.trendScore = trendScore
        self.momentumScore = momentumScore
        self.volatilityRisk = volatilityRisk
        self.capitalAddon = capitalAddon
        self.shortAddon = shortAddon
        self.insiderAddon = insiderAddon
    }
}

public struct AdvisorSymbolResponse: Codable {
    public let ok: Bool?
    public let updatedAt: String?
    public let code: String?
    public let position: AdvisorPosition?
    public let advice: AdvisorPosition?
    public let error: String?

    public enum CodingKeys: String, CodingKey {
        case ok
        case updatedAt = "updated_at"
        case code
        case position
        case advice
        case error
    }

    public init(ok: Bool?, updatedAt: String?, code: String?, position: AdvisorPosition?, advice: AdvisorPosition?, error: String?) {
        self.ok = ok
        self.updatedAt = updatedAt
        self.code = code
        self.position = position
        self.advice = advice
        self.error = error
    }
}

public struct AdvisorCandidateResponse: Codable {
    public let ok: Bool?
    public let updatedAt: String?
    public let code: String?
    public let signal: String?
    public let shouldNotify: Bool?
    public let observationWindowDays: Int?
    public let advice: AdvisorPosition?
    public let error: String?

    public enum CodingKeys: String, CodingKey {
        case ok
        case updatedAt = "updated_at"
        case code
        case signal
        case shouldNotify = "should_notify"
        case observationWindowDays = "observation_window_days"
        case advice
        case error
    }

    public init(ok: Bool?, updatedAt: String?, code: String?, signal: String?, shouldNotify: Bool?, observationWindowDays: Int?, advice: AdvisorPosition?, error: String?) {
        self.ok = ok
        self.updatedAt = updatedAt
        self.code = code
        self.signal = signal
        self.shouldNotify = shouldNotify
        self.observationWindowDays = observationWindowDays
        self.advice = advice
        self.error = error
    }
}

public struct AdvisorAlertsResponse: Codable {
    public let ok: Bool
    public let updatedAt: String?
    public let count: Int?
    public let alerts: [AdvisorAlert]
    public let error: String?

    public enum CodingKeys: String, CodingKey {
        case ok
        case updatedAt = "updated_at"
        case count
        case alerts
        case error
    }

    public init(ok: Bool, updatedAt: String?, count: Int?, alerts: [AdvisorAlert], error: String?) {
        self.ok = ok
        self.updatedAt = updatedAt
        self.count = count
        self.alerts = alerts
        self.error = error
    }
}

public struct AdvisorAlert: Codable, Identifiable {
    public let id: String
    public let source: String?
    public let code: String?
    public let name: String?
    public let alertType: String?
    public let signal: String?
    public let createdAt: String?
    public let price: Double?
    public let triggerPrice: Double?
    public let triggerCondition: String?
    public let quoteTime: String?
    public let suggestion: String?
    public let reasons: [String]?
    public let tradePlan: AdvisorTradePlan?
    public let technicalScore: Double?
    public let riskScore: Double?
    public let unrealizedPL: Double?
    public let plRatio: Double?
    public let acknowledged: Bool?

    public enum CodingKeys: String, CodingKey {
        case id
        case source
        case code
        case name
        case alertType = "alert_type"
        case signal
        case createdAt = "created_at"
        case price
        case triggerPrice = "trigger_price"
        case triggerCondition = "trigger_condition"
        case quoteTime = "quote_time"
        case suggestion
        case reasons
        case tradePlan = "trade_plan"
        case technicalScore = "technical_score"
        case riskScore = "risk_score"
        case unrealizedPL = "unrealized_pl"
        case plRatio = "pl_ratio"
        case acknowledged
    }

    public init(id: String, source: String?, code: String?, name: String?, alertType: String?, signal: String?, createdAt: String?, price: Double?, triggerPrice: Double?, triggerCondition: String?, quoteTime: String?, suggestion: String?, reasons: [String]?, tradePlan: AdvisorTradePlan?, technicalScore: Double?, riskScore: Double?, unrealizedPL: Double?, plRatio: Double?, acknowledged: Bool?) {
        self.id = id
        self.source = source
        self.code = code
        self.name = name
        self.alertType = alertType
        self.signal = signal
        self.createdAt = createdAt
        self.price = price
        self.triggerPrice = triggerPrice
        self.triggerCondition = triggerCondition
        self.quoteTime = quoteTime
        self.suggestion = suggestion
        self.reasons = reasons
        self.tradePlan = tradePlan
        self.technicalScore = technicalScore
        self.riskScore = riskScore
        self.unrealizedPL = unrealizedPL
        self.plRatio = plRatio
        self.acknowledged = acknowledged
    }
}

