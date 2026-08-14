//
//  AdvisorViewModel.swift
//  PortSight
//
//  Created by Codex on 26/5/2026.
//

import Combine
import Foundation

struct AdvisorSummaryResponse: Codable {
    let ok: Bool
    let updatedAt: String?
    let portfolio: AdvisorPortfolio?
    let positions: [AdvisorPosition]
    let alerts: [AdvisorAlert]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case updatedAt = "updated_at"
        case portfolio
        case positions
        case alerts
        case error
    }
}

struct AdvisorPortfolio: Codable {
    let marketValue: Double?
    let riskScore: Double?
    let score: Double?
    let rating: String?
    let ratingLabel: String?
    let ratingDescription: String?
    let scoreRanges: [AdvisorScoreRange]?
    let pnl: AdvisorPnL?
    let suggestion: String?
    let reasons: [String]?
    let sectorExposure: [String: Double]?
    let correlation: AdvisorCorrelation?

    enum CodingKeys: String, CodingKey {
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
}

struct AdvisorScoreRange: Codable {
    let min: Double
    let max: Double
    let rating: String
    let label: String
}

struct AdvisorPnL: Codable {
    let unrealizedPL: Double?
    let realizedPL: Double?
    let totalPL: Double?
    let plRatio: Double?

    enum CodingKeys: String, CodingKey {
        case unrealizedPL = "unrealized_pl"
        case realizedPL = "realized_pl"
        case totalPL = "total_pl"
        case plRatio = "pl_ratio"
    }
}

struct AdvisorCorrelation: Codable {
    let pairs: [AdvisorCorrelationPair]?
}

struct AdvisorCorrelationPair: Codable, Identifiable {
    var id: String { "\(left)-\(right)" }

    let left: String
    let right: String
    let correlation: Double
}

struct AdvisorPosition: Codable, Identifiable {
    var id: String { code }

    let code: String
    let name: String?
    let sector: String?
    let weight: Double?
    let qty: Double?
    let costPrice: Double?
    let marketValue: Double?
    let close: Double?
    let realizedPL: Double?
    let unrealizedPL: Double?
    let plRatio: Double?
    let riskScore: Double?
    let technicalScore: Double?
    let confirmed: Bool?
    let action: String?
    let suggestion: String?
    let reasons: [String]?
    let tradePlan: AdvisorTradePlan?
    let prediction: AdvisorPrediction?
    let signals: AdvisorSignals?
    let profile: AdvisorProfile?
    let priceStructure: AdvisorPriceStructure?
    let analysisPoints: [AdvisorAnalysisPoint]?
    let scoreBreakdown: AdvisorScoreBreakdown?

    enum CodingKeys: String, CodingKey {
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
}

struct AdvisorTradePlan: Codable {
    let alertType: String?
    let buyPercent: Double?
    let sellPercent: Double?
    let sellQty: Double?
    let triggerPrice: Double?
    let triggerCondition: String?
    let basis: String?

    enum CodingKeys: String, CodingKey {
        case alertType = "alert_type"
        case buyPercent = "buy_percent"
        case sellPercent = "sell_percent"
        case sellQty = "sell_qty"
        case triggerPrice = "trigger_price"
        case triggerCondition = "trigger_condition"
        case basis
    }
}

struct AdvisorPrediction: Codable {
    let expectedVolatility30d: Double?
    let trend5d: Double?
    let trend20d: Double?
    let trend60d: Double?
    let drawdownFromHigh: Double?
    let expectedByHorizon: [String: AdvisorHorizonExpectation]?

    enum CodingKeys: String, CodingKey {
        case expectedVolatility30d = "expected_volatility_30d"
        case trend5d = "trend_5d"
        case trend20d = "trend_20d"
        case trend60d = "trend_60d"
        case drawdownFromHigh = "drawdown_from_high"
        case expectedByHorizon = "expected_by_horizon"
    }
}

struct AdvisorHorizonExpectation: Codable {
    let expectedReturn: Double?
    let expectedVolatility: Double?
    let expectedMaxDrawdown: Double?

    enum CodingKeys: String, CodingKey {
        case expectedReturn = "expected_return"
        case expectedVolatility = "expected_volatility"
        case expectedMaxDrawdown = "expected_max_drawdown"
    }
}

struct AdvisorSignals: Codable {
    let daily: AdvisorDailySignals?
    let weekly: AdvisorWeeklySignals?
    let monthly: AdvisorMonthlySignals?
}

struct AdvisorDailySignals: Codable {
    let ma20: Double?
    let ma60: Double?
    let rsi14: Double?
    let volatility60d: Double?
    let volatilityTier: String?

    enum CodingKeys: String, CodingKey {
        case ma20
        case ma60
        case rsi14
        case volatility60d = "volatility_60d"
        case volatilityTier = "volatility_tier"
    }
}

struct AdvisorWeeklySignals: Codable {
    let bollPosition: Double?
    let close: Double?

    enum CodingKeys: String, CodingKey {
        case bollPosition = "boll_position"
        case close
    }
}

struct AdvisorMonthlySignals: Codable {
    let close: Double?
    let ma20: Double?
}

struct AdvisorProfile: Codable {
    let riskTier: String?
    let sizeTier: String?
    let volatilityTier: String?
    let personality: AdvisorPersonality?

    enum CodingKeys: String, CodingKey {
        case riskTier = "risk_tier"
        case sizeTier = "size_tier"
        case volatilityTier = "volatility_tier"
        case personality
    }
}

struct AdvisorPersonality: Codable {
    let type: String?
    let traits: [String]?
    let rsiHotThreshold: Double?
    let maxBuyPercent: Double?
    let strategyNote: String?

    enum CodingKeys: String, CodingKey {
        case type
        case traits
        case rsiHotThreshold = "rsi_hot_threshold"
        case maxBuyPercent = "max_buy_percent"
        case strategyNote = "strategy_note"
    }
}

struct AdvisorPriceStructure: Codable {
    let status: String?
    let score: Double?
    let points: [String]?
    let recentHigh20: Double?
    let recentLow20: Double?
    let volumeExpansion: Bool?

    enum CodingKeys: String, CodingKey {
        case status
        case score
        case points
        case recentHigh20 = "recent_high_20"
        case recentLow20 = "recent_low_20"
        case volumeExpansion = "volume_expansion"
    }
}

struct AdvisorAnalysisPoint: Codable, Identifiable {
    var id: String { "\(category ?? "")-\(label ?? "")-\(detail ?? "")" }

    let category: String?
    let label: String?
    let status: String?
    let detail: String?
}

struct AdvisorScoreBreakdown: Codable {
    let trendScore: Double?
    let momentumScore: Double?
    let volatilityRisk: Double?
    let capitalAddon: Double?
    let shortAddon: Double?
    let insiderAddon: Double?

    enum CodingKeys: String, CodingKey {
        case trendScore = "trend_score"
        case momentumScore = "momentum_score"
        case volatilityRisk = "volatility_risk"
        case capitalAddon = "capital_addon"
        case shortAddon = "short_addon"
        case insiderAddon = "insider_addon"
    }
}

struct AdvisorSymbolResponse: Codable {
    let ok: Bool?
    let updatedAt: String?
    let code: String?
    let position: AdvisorPosition?
    let advice: AdvisorPosition?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case updatedAt = "updated_at"
        case code
        case position
        case advice
        case error
    }
}

struct AdvisorCandidateResponse: Codable {
    let ok: Bool?
    let updatedAt: String?
    let code: String?
    let signal: String?
    let shouldNotify: Bool?
    let observationWindowDays: Int?
    let advice: AdvisorPosition?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case updatedAt = "updated_at"
        case code
        case signal
        case shouldNotify = "should_notify"
        case observationWindowDays = "observation_window_days"
        case advice
        case error
    }
}

struct AdvisorAlertsResponse: Codable {
    let ok: Bool
    let updatedAt: String?
    let count: Int?
    let alerts: [AdvisorAlert]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case updatedAt = "updated_at"
        case count
        case alerts
        case error
    }
}

struct AdvisorAlert: Codable, Identifiable {
    let id: String
    let source: String?
    let code: String?
    let name: String?
    let alertType: String?
    let signal: String?
    let createdAt: String?
    let price: Double?
    let triggerPrice: Double?
    let triggerCondition: String?
    let quoteTime: String?
    let suggestion: String?
    let reasons: [String]?
    let tradePlan: AdvisorTradePlan?
    let technicalScore: Double?
    let riskScore: Double?
    let unrealizedPL: Double?
    let plRatio: Double?
    let acknowledged: Bool?

    enum CodingKeys: String, CodingKey {
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
}

@MainActor
final class AdvisorViewModel: ObservableObject {
    @Published private(set) var summary: AdvisorSummaryResponse?
    @Published private(set) var suggestions: AdvisorSummaryResponse?
    @Published private(set) var symbolPositions: [String: AdvisorPosition] = [:]
    @Published private(set) var candidatePositions: [String: AdvisorPosition] = [:]
    @Published private(set) var alerts: [AdvisorAlert] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private static var memorySummary: AdvisorSummaryResponse?
    private static var memorySuggestions: AdvisorSummaryResponse?
    private static var memorySymbolPositions: [String: AdvisorPosition] = [:]
    private static var memoryCandidatePositions: [String: AdvisorPosition] = [:]
    private static var memoryAlerts: [AdvisorAlert] = []
    private static var lastSummaryRefreshAt: Date?
    private static var lastSuggestionsRefreshAt: Date?
    private static var lastSymbolRefreshAt: [String: Date] = [:]
    private static var lastCandidateRefreshAt: [String: Date] = [:]
    private static var lastAlertsRefreshAt: Date?

    private let summaryCacheKey = "advisor_summary_cache_v1"
    private let suggestionsCacheKey = "advisor_suggestions_cache_v1"
    private let alertsCacheKey = "advisor_alerts_cache_v1"

    init() {
        loadMemory()
    }

    var portfolio: AdvisorPortfolio? {
        suggestions?.portfolio ?? summary?.portfolio
    }

    var reportPositions: [AdvisorPosition] {
        suggestions?.positions ?? summary?.positions ?? []
    }

    func position(for symbol: String) -> AdvisorPosition? {
        let ticker = Self.normalizedTicker(symbol)
        if let detailed = symbolPositions[ticker] {
            return detailed
        }
        if let suggested = suggestions?.positions.first(where: { Self.normalizedTicker($0.code) == ticker }) {
            return suggested
        }
        return summary?.positions.first { Self.normalizedTicker($0.code) == ticker }
    }

    func loadCache() {
        loadMemory()

        if summary == nil,
           let cached = CacheManager.load(AdvisorSummaryResponse.self, key: summaryCacheKey),
           cached.ok {
            applySummary(cached)
        }

        if suggestions == nil,
           let cached = CacheManager.load(AdvisorSummaryResponse.self, key: suggestionsCacheKey),
           cached.ok {
            applySuggestions(cached)
        }

        if alerts.isEmpty,
           let cached = CacheManager.load(AdvisorAlertsResponse.self, key: alertsCacheKey),
           cached.ok {
            applyAlerts(cached.alerts)
        }
    }

    func loadMemorySnapshot() {
        loadMemory()
    }

    func loadSymbolCache(symbol: String) {
        let ticker = Self.normalizedTicker(symbol)
        loadMemory()

        if symbolPositions[ticker] == nil,
           let cached = CacheManager.load(AdvisorPosition.self, key: symbolCacheKey(for: ticker)) {
            applySymbolPosition(cached, ticker: ticker)
        }
    }

    func loadCandidateCache(symbol: String) {
        let ticker = Self.normalizedTicker(symbol)
        loadMemory()

        if candidatePositions[ticker] == nil,
           let cached = CacheManager.load(AdvisorPosition.self, key: candidateCacheKey(for: ticker)) {
            applyCandidatePosition(cached, ticker: ticker)
        }
    }

    func fetchSummary(refresh: Bool = false, minimumInterval: TimeInterval = 60) async {
        guard refresh || shouldRefresh(Self.lastSummaryRefreshAt, minimumInterval: minimumInterval) else { return }
        guard let url = BackendConfig.url(
            path: "advisor/summary",
            queryItems: refresh ? [URLQueryItem(name: "refresh", value: "true")] : []
        ) else {
            errorMessage = "URL 错误"
            return
        }

        isLoading = summary == nil
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try await CacheManager.decode(AdvisorSummaryResponse.self, from: data)
            guard result.ok else {
                errorMessage = result.error
                return
            }

            applySummary(result)
            Self.lastSummaryRefreshAt = Date()
            await CacheManager.saveAsync(result, key: summaryCacheKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchSuggestions(refresh: Bool = false, minimumInterval: TimeInterval = 60) async {
        guard refresh || shouldRefresh(Self.lastSuggestionsRefreshAt, minimumInterval: minimumInterval) else { return }
        guard let url = BackendConfig.url(
            path: "advisor/suggestions",
            queryItems: [URLQueryItem(name: "refresh", value: refresh ? "true" : "false")]
        ) else {
            errorMessage = "URL 错误"
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try await CacheManager.decode(AdvisorSummaryResponse.self, from: data)
            guard result.ok else {
                errorMessage = result.error
                return
            }

            applySuggestions(result)
            Self.lastSuggestionsRefreshAt = Date()
            await CacheManager.saveAsync(result, key: suggestionsCacheKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchSymbol(symbol: String, refresh: Bool = false, minimumInterval: TimeInterval = 60) async {
        let backendSymbol = Self.backendSymbol(symbol)
        let ticker = Self.normalizedTicker(backendSymbol)
        guard refresh || shouldRefresh(Self.lastSymbolRefreshAt[ticker], minimumInterval: minimumInterval) else { return }
        guard let url = BackendConfig.url(
            path: "advisor/symbol",
            queryItems: [
                URLQueryItem(name: "symbol", value: backendSymbol),
                URLQueryItem(name: "refresh", value: refresh ? "true" : "false")
            ]
        ) else {
            errorMessage = "URL 错误"
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let position = try await decodeSymbolPosition(from: data)
            applySymbolPosition(position, ticker: ticker)
            Self.lastSymbolRefreshAt[ticker] = Date()
            await CacheManager.saveAsync(position, key: symbolCacheKey(for: ticker))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchCandidate(symbol: String, refresh: Bool = false, minimumInterval: TimeInterval = 60) async {
        let backendSymbol = Self.backendSymbol(symbol)
        let ticker = Self.normalizedTicker(backendSymbol)
        guard refresh || shouldRefresh(Self.lastCandidateRefreshAt[ticker], minimumInterval: minimumInterval) else { return }
        guard let url = BackendConfig.url(
            path: "advisor/candidate",
            queryItems: [
                URLQueryItem(name: "symbol", value: backendSymbol),
                URLQueryItem(name: "refresh", value: refresh ? "true" : "false")
            ]
        ) else {
            errorMessage = "URL 错误"
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try await CacheManager.decode(AdvisorCandidateResponse.self, from: data)
            guard result.ok != false, let position = result.advice else {
                errorMessage = result.error
                return
            }

            applyCandidatePosition(position, ticker: ticker)
            Self.lastCandidateRefreshAt[ticker] = Date()
            await CacheManager.saveAsync(position, key: candidateCacheKey(for: ticker))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchAlerts(includeAcknowledged: Bool = false, minimumInterval: TimeInterval = 60) async {
        guard shouldRefresh(Self.lastAlertsRefreshAt, minimumInterval: minimumInterval) else { return }
        guard let url = BackendConfig.url(
            path: "advisor/alerts",
            queryItems: includeAcknowledged ? [URLQueryItem(name: "include_acknowledged", value: "true")] : []
        ) else {
            errorMessage = "URL 错误"
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try await CacheManager.decode(AdvisorAlertsResponse.self, from: data)
            guard result.ok else {
                errorMessage = result.error
                return
            }

            applyAlerts(result.alerts)
            Self.lastAlertsRefreshAt = Date()
            await CacheManager.saveAsync(result, key: alertsCacheKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMemory() {
        if let memorySummary = Self.memorySummary {
            summary = memorySummary
        }

        if let memorySuggestions = Self.memorySuggestions {
            suggestions = memorySuggestions
        }

        if !Self.memorySymbolPositions.isEmpty {
            symbolPositions = Self.memorySymbolPositions
        }

        if !Self.memoryCandidatePositions.isEmpty {
            candidatePositions = Self.memoryCandidatePositions
        }

        if !Self.memoryAlerts.isEmpty {
            alerts = Self.memoryAlerts
        }
    }

    private func applySummary(_ result: AdvisorSummaryResponse) {
        summary = result
        Self.memorySummary = result
        errorMessage = nil
    }

    private func applySuggestions(_ result: AdvisorSummaryResponse) {
        suggestions = result
        Self.memorySuggestions = result
        errorMessage = nil
    }

    private func applySymbolPosition(_ position: AdvisorPosition, ticker: String) {
        symbolPositions[ticker] = position
        Self.memorySymbolPositions[ticker] = position
        errorMessage = nil
    }

    private func applyCandidatePosition(_ position: AdvisorPosition, ticker: String) {
        candidatePositions[ticker] = position
        Self.memoryCandidatePositions[ticker] = position
        errorMessage = nil
    }

    private func applyAlerts(_ result: [AdvisorAlert]) {
        alerts = result
        Self.memoryAlerts = result
        errorMessage = nil
    }

    private func shouldRefresh(_ date: Date?, minimumInterval: TimeInterval) -> Bool {
        guard let date else { return true }
        return Date().timeIntervalSince(date) >= minimumInterval
    }

    private func decodeSymbolPosition(from data: Data) async throws -> AdvisorPosition {
        if let direct = try? await CacheManager.decode(AdvisorPosition.self, from: data) {
            return direct
        }

        let envelope = try await CacheManager.decode(AdvisorSymbolResponse.self, from: data)
        if let position = envelope.position ?? envelope.advice {
            return position
        }

        throw DecodingError.valueNotFound(
            AdvisorPosition.self,
            DecodingError.Context(
                codingPath: [],
                debugDescription: envelope.error ?? "Missing advisor symbol position"
            )
        )
    }

    private func symbolCacheKey(for ticker: String) -> String {
        "advisor_symbol_cache_v1_\(ticker)"
    }

    private func candidateCacheKey(for ticker: String) -> String {
        "advisor_candidate_cache_v1_\(ticker)"
    }

    private static func backendSymbol(_ symbol: String) -> String {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains(".") ? trimmed.uppercased() : "US.\(trimmed.uppercased())"
    }

    private static func normalizedTicker(_ symbol: String) -> String {
        symbol.split(separator: ".").last.map(String.init)?.uppercased() ?? symbol.uppercased()
    }
}
