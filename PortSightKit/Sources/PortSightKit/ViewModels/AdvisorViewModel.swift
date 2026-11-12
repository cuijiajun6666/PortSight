import Foundation
import Combine
@MainActor
public final class AdvisorViewModel: ObservableObject {
    @Published public private(set) var summary: AdvisorSummaryResponse?
    @Published public private(set) var suggestions: AdvisorSummaryResponse?
    @Published public private(set) var symbolPositions: [String: AdvisorPosition] = [:]
    @Published public private(set) var candidatePositions: [String: AdvisorPosition] = [:]
    @Published public private(set) var alerts: [AdvisorAlert] = []
    @Published public private(set) var isLoading = false
    @Published public var errorMessage: String?

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

    public init() {
        if DemoPortfolioData.enabled { loadDemo(); return }
        loadMemory()
    }

    /// Kept for the pages that ask: no longer set (the built-in analysis is shown, over the holdings on screen —
    /// real and built-in — until the relay has an AI analysis).
    @Published public private(set) var missingNote: String?

    public func loadDemo(scope: PortfolioScope = .all) {
        missingNote = nil
        let rows: [[String: Any]] = Portfolio.combined(scope).map { h in
            ["code": h.symbol, "name": h.name, "qty": h.quantity, "cost_price": h.cost,
             "market_val": h.value, "close": h.price, "unrealized_pl": h.pnl,
             "pl_ratio": h.quantity * h.cost == 0 ? 0 : h.pnl / (h.quantity * h.cost) * 100, "weight": h.value / max(Portfolio.total(scope), 1),
             "risk_score": 32, "technical_score": 82, "action": "watch", "confirmed": false,
             "suggestion": "关注趋势和组合敞口", "reasons": ["趋势仍向上，组合敞口集中在科技股"]]
        }
        let total = Portfolio.total(scope), pnl = Portfolio.pnl(scope)
        let object: [String: Any] = ["ok": true, "updated_at": "2026-10-23T20:00:00Z",
            "portfolio": ["market_value": total, "risk_score": 32, "score": 87, "rating": "good", "rating_label": "Good",
                "rating_description": "资产较分散，关注个人与量化的重复持仓。",
                "suggestion": "维持现金缓冲，按计划复核趋势。",
                "pnl": ["total_pl": pnl, "unrealized_pl": pnl, "realized_pl": 0, "pl_ratio": pnl / max(Portfolio.principal(scope), 1) * 100]],
            "positions": rows, "alerts": []]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let result = try? JSONDecoder().decode(AdvisorSummaryResponse.self, from: data) else { return }
        summary = result; suggestions = result; errorMessage = nil
    }

    public var portfolio: AdvisorPortfolio? {
        suggestions?.portfolio ?? summary?.portfolio
    }

    public var reportPositions: [AdvisorPosition] {
        suggestions?.positions ?? summary?.positions ?? []
    }

    public func position(for symbol: String) -> AdvisorPosition? {
        let ticker = Self.normalizedTicker(symbol)
        if let detailed = symbolPositions[ticker] {
            return detailed
        }
        if let suggested = suggestions?.positions.first(where: { Self.normalizedTicker($0.code) == ticker }) {
            return suggested
        }
        return summary?.positions.first { Self.normalizedTicker($0.code) == ticker }
    }

    public func loadCache() {
        if DemoPortfolioData.enabled { return }
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

    public func loadMemorySnapshot() {
        if DemoPortfolioData.enabled { return }
        loadMemory()
    }

    public func loadSymbolCache(symbol: String) {
        if DemoPortfolioData.enabled { return }
        let ticker = Self.normalizedTicker(symbol)
        loadMemory()

        if symbolPositions[ticker] == nil,
           let cached = CacheManager.load(AdvisorPosition.self, key: symbolCacheKey(for: ticker)) {
            applySymbolPosition(cached, ticker: ticker)
        }
    }

    public func loadCandidateCache(symbol: String) {
        if DemoPortfolioData.enabled { return }
        let ticker = Self.normalizedTicker(symbol)
        loadMemory()

        if candidatePositions[ticker] == nil,
           let cached = CacheManager.load(AdvisorPosition.self, key: candidateCacheKey(for: ticker)) {
            applyCandidatePosition(cached, ticker: ticker)
        }
    }

    public func fetchSummary(refresh: Bool = false, minimumInterval: TimeInterval = 60) async {
        if DemoPortfolioData.enabled { return }
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

    public func fetchSuggestions(refresh: Bool = false, minimumInterval: TimeInterval = 60) async {
        if DemoPortfolioData.enabled { return }
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

    public func fetchSymbol(symbol: String, refresh: Bool = false, minimumInterval: TimeInterval = 60) async {
        if DemoPortfolioData.enabled { return }
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

    public func fetchCandidate(symbol: String, refresh: Bool = false, minimumInterval: TimeInterval = 60) async {
        if DemoPortfolioData.enabled { return }
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

    public func fetchAlerts(includeAcknowledged: Bool = false, minimumInterval: TimeInterval = 60) async {
        if DemoPortfolioData.enabled { return }
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
