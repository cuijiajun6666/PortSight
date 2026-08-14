//
//  分时图.swift
//  PortSight
//
//  Created by Chris Cui on 17/5/2026.
//

import Charts
import SwiftUI
import Foundation
import Combine

struct IntradayPricePoint: Codable, Identifiable, Equatable {
    var id: String { "\(code)-\(time)" }

    let code: String
    let name: String?
    let time: String
    let isBlank: Bool
    let openedMins: Int?
    let curPrice: Double
    let lastClose: Double?
    let avgPrice: Double?
    let volume: Double?
    let turnover: Double?

    var date: Date? {
        Self.dateFormatter.date(from: time)
            ?? Self.fractionalDateFormatter.date(from: time)
    }

    var isRegularTradingMinute: Bool {
        guard let minute = openedMins ?? minuteOfDayFromTimeString else {
            return false
        }

        return (9 * 60 + 30)...(16 * 60) ~= minute
    }

    private var minuteOfDayFromTimeString: Int? {
        let parts = time.split(separator: " ")
        guard parts.count == 2 else { return nil }

        let timeParts = parts[1].split(separator: ":")
        guard timeParts.count >= 2,
              let hour = Int(timeParts[0]),
              let minute = Int(timeParts[1]) else {
            return nil
        }

        return hour * 60 + minute
    }

    enum CodingKeys: String, CodingKey {
        case code
        case name
        case time
        case isBlank = "is_blank"
        case openedMins = "opened_mins"
        case curPrice = "cur_price"
        case lastClose = "last_close"
        case avgPrice = "avg_price"
        case volume
        case turnover
    }

    init(
        code: String,
        name: String? = nil,
        time: String,
        isBlank: Bool = false,
        openedMins: Int? = nil,
        curPrice: Double,
        lastClose: Double? = nil,
        avgPrice: Double? = nil,
        volume: Double? = nil,
        turnover: Double? = nil
    ) {
        self.code = code
        self.name = name
        self.time = time
        self.isBlank = isBlank
        self.openedMins = openedMins
        self.curPrice = curPrice
        self.lastClose = lastClose
        self.avgPrice = avgPrice
        self.volume = volume
        self.turnover = turnover
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        code = try container.decodeIfPresent(String.self, forKey: .code) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name)
        time = try container.decode(String.self, forKey: .time)
        isBlank = try container.decodeIfPresent(Bool.self, forKey: .isBlank) ?? false
        openedMins = try container.decodeIfPresent(Int.self, forKey: .openedMins)
        curPrice = try container.decode(Double.self, forKey: .curPrice)
        lastClose = try container.decodeIfPresent(Double.self, forKey: .lastClose)
        avgPrice = try container.decodeIfPresent(Double.self, forKey: .avgPrice)
        volume = try container.decodeIfPresent(Double.self, forKey: .volume)
        turnover = try container.decodeIfPresent(Double.self, forKey: .turnover)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(code, forKey: .code)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(time, forKey: .time)
        try container.encode(isBlank, forKey: .isBlank)
        try container.encodeIfPresent(openedMins, forKey: .openedMins)
        try container.encode(curPrice, forKey: .curPrice)
        try container.encodeIfPresent(lastClose, forKey: .lastClose)
        try container.encodeIfPresent(avgPrice, forKey: .avgPrice)
        try container.encodeIfPresent(volume, forKey: .volume)
        try container.encodeIfPresent(turnover, forKey: .turnover)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let fractionalDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

}

struct IntradayMarketResponse: Codable {
    let ok: Bool
    let source: String?
    let marketOpen: Bool?
    let tradingDate: String?
    let refreshIntervalSeconds: Double?
    let codes: [String]?
    let summary: [String: IntradayMarketSummary]?
    let data: [String: [IntradayPricePoint]]?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case source
        case marketOpen = "market_open"
        case tradingDate = "trading_date"
        case refreshIntervalSeconds = "refresh_interval_seconds"
        case codes
        case summary
        case data
        case error
    }

    func points(for symbol: String) -> [IntradayPricePoint] {
        guard let data else { return [] }

        for key in candidateDataKeys(for: symbol) {
            if let points = data[key] {
                return points
            }
        }

        return data.first?.value ?? []
    }

    private func candidateDataKeys(for symbol: String) -> [String] {
        let uppercasedSymbol = symbol.uppercased()
        let shortSymbol = uppercasedSymbol
            .replacingOccurrences(of: "US.", with: "")

        var keys = [
            uppercasedSymbol,
            "US.\(shortSymbol)"
        ]

        switch shortSymbol {
        case "SPX", "SPY":
            keys.append("US.SPY")
        case "IXIC", "QQQ":
            keys.append("US.QQQ")
        case "DJI", "DIA":
            keys.append("US.DIA")
        default:
            break
        }

        return keys.reduce(into: [String]()) { result, key in
            guard !result.contains(key) else { return }
            result.append(key)
        }
    }

    func summary(for symbol: String) -> IntradayMarketSummary? {
        guard let summary else { return nil }

        for key in candidateDataKeys(for: symbol) {
            if let item = summary[key] {
                return item
            }
        }

        return summary.first?.value
    }
}

struct IntradayMarketSummary: Codable, Equatable {
    let code: String
    let chartCode: String?
    let quoteCode: String?
    let name: String?
    let price: Double?
    let previousClose: Double?
    let change: Double?
    let changePercent: Double?
    let latestTime: String?
    let points: Int?
    let quoteError: String?

    enum CodingKeys: String, CodingKey {
        case code
        case chartCode = "chart_code"
        case quoteCode = "quote_code"
        case name
        case price
        case previousClose = "previous_close"
        case change
        case changePercent = "change_percent"
        case latestTime = "latest_time"
        case points
        case quoteError = "quote_error"
    }
}

struct IntradayMarketCache: Codable {
    let tradingDate: String
    let source: String?
    let marketOpen: Bool
    let refreshIntervalSeconds: Double
    let points: [IntradayPricePoint]
    let summary: IntradayMarketSummary?
}

func loadCachedIntradaySparklinePrices(
    symbols: [String],
    maximumPointCount: Int
) -> [String: [Double]] {
    var result: [String: [Double]] = [:]

    for symbol in symbols {
        guard let latestDate = UserDefaults.standard.string(
            forKey: intradayLatestDateKey(symbol: symbol)
        ),
        let cached = CacheManager.load(
            IntradayMarketCache.self,
            key: intradayCacheKey(symbol: symbol, tradingDate: latestDate)
        ) else {
            continue
        }

        let prices = cached.points
            .filter { !$0.isBlank && $0.curPrice > 0 }
            .map(\.curPrice)

        guard !prices.isEmpty else { continue }
        result[symbol] = sampledIntradayPrices(prices, maximumPointCount: maximumPointCount)
    }

    return result
}

func fetchIntradaySparklinePrices(
    symbols: [String],
    maximumPointCount: Int
) async -> [String: [Double]] {
    let uniqueSymbols = Array(Set(symbols)).sorted()
    guard !uniqueSymbols.isEmpty,
          let url = BackendConfig.url(
            path: "market",
            queryItems: uniqueSymbols.map { URLQueryItem(name: "symbol", value: $0) }
          ) else {
        return loadCachedIntradaySparklinePrices(
            symbols: uniqueSymbols,
            maximumPointCount: maximumPointCount
        )
    }

    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        let result = try await CacheManager.decode(IntradayMarketResponse.self, from: data)
        guard result.ok else {
            return loadCachedIntradaySparklinePrices(
                symbols: uniqueSymbols,
                maximumPointCount: maximumPointCount
            )
        }

        var fetchedPrices: [String: [Double]] = [:]

        for symbol in uniqueSymbols {
            let points = normalizedIntradayPoints(
                result.points(for: symbol),
                marketOpen: result.marketOpen ?? false
            )
            guard !points.isEmpty,
                  let tradingDate = result.tradingDate,
                  !tradingDate.isEmpty else {
                continue
            }

            let cache = mergedIntradayCache(
                IntradayMarketCache(
                tradingDate: tradingDate,
                source: result.source,
                marketOpen: result.marketOpen ?? false,
                refreshIntervalSeconds: result.refreshIntervalSeconds ?? 60,
                points: points,
                summary: result.summary(for: symbol)
                ),
                symbol: symbol
            )

            await saveIntradayCache(cache, symbol: symbol)
            fetchedPrices[symbol] = sampledIntradayPrices(
                points.map(\.curPrice),
                maximumPointCount: maximumPointCount
            )
        }

        if fetchedPrices.isEmpty {
            return loadCachedIntradaySparklinePrices(
                symbols: uniqueSymbols,
                maximumPointCount: maximumPointCount
            )
        }

        return fetchedPrices
    } catch {
        return loadCachedIntradaySparklinePrices(
            symbols: uniqueSymbols,
            maximumPointCount: maximumPointCount
        )
    }
}

private func sampledIntradayPrices(
    _ prices: [Double],
    maximumPointCount: Int
) -> [Double] {
    guard maximumPointCount > 2,
          prices.count > maximumPointCount else {
        return prices
    }

    let step = Double(prices.count - 1) / Double(maximumPointCount - 1)
    var indices = Set<Int>()

    for offset in 0..<maximumPointCount {
        indices.insert(Int((Double(offset) * step).rounded()))
    }

    return indices.sorted().map { prices[$0] }
}

private func intradayCacheKey(symbol: String, tradingDate: String) -> String {
    "intraday_market_\(intradayNormalizedSymbolKey(symbol))_\(tradingDate)"
}

private func intradayLatestDateKey(symbol: String) -> String {
    "intraday_market_\(intradayNormalizedSymbolKey(symbol))_latest_date"
}

private func intradayNormalizedSymbolKey(_ symbol: String) -> String {
    symbol
        .uppercased()
        .replacingOccurrences(of: ".", with: "_")
        .replacingOccurrences(of: "-", with: "_")
}

private func intradayCachedDatesKey(symbol: String) -> String {
    "intraday_market_\(intradayNormalizedSymbolKey(symbol))_cached_dates"
}

private func saveIntradayCache(_ cache: IntradayMarketCache, symbol: String) async {
    let datesKey = intradayCachedDatesKey(symbol: symbol)
    let cachedDates = UserDefaults.standard.stringArray(forKey: datesKey) ?? []

    await CacheManager.saveAsync(
        cache,
        key: intradayCacheKey(symbol: symbol, tradingDate: cache.tradingDate)
    )
    UserDefaults.standard.set(cache.tradingDate, forKey: intradayLatestDateKey(symbol: symbol))

    if cache.marketOpen {
        for cachedDate in cachedDates where cachedDate != cache.tradingDate {
            UserDefaults.standard.removeObject(
                forKey: intradayCacheKey(symbol: symbol, tradingDate: cachedDate)
            )
        }
        UserDefaults.standard.set([cache.tradingDate], forKey: datesKey)
    } else if !cachedDates.contains(cache.tradingDate) {
        UserDefaults.standard.set(cachedDates + [cache.tradingDate], forKey: datesKey)
    }
}

private func mergedIntradayCache(
    _ incoming: IntradayMarketCache,
    symbol: String
) -> IntradayMarketCache {
    guard let cached = CacheManager.load(
        IntradayMarketCache.self,
        key: intradayCacheKey(symbol: symbol, tradingDate: incoming.tradingDate)
    ) else {
        return incoming
    }

    let points = mergeIntradayPoints(
        cached.points,
        with: incoming.points,
        marketOpen: incoming.marketOpen
    )

    return IntradayMarketCache(
        tradingDate: incoming.tradingDate,
        source: incoming.source ?? cached.source,
        marketOpen: incoming.marketOpen,
        refreshIntervalSeconds: incoming.refreshIntervalSeconds,
        points: points,
        summary: incoming.summary ?? cached.summary
    )
}

private func mergeIntradayPoints(
    _ cachedPoints: [IntradayPricePoint],
    with incomingPoints: [IntradayPricePoint],
    marketOpen: Bool
) -> [IntradayPricePoint] {
    let mergedByMinute = cachedPoints.reduce(into: [String: IntradayPricePoint]()) { points, point in
        points[point.time] = point
    }

    let merged = incomingPoints.reduce(into: mergedByMinute) { points, point in
        points[point.time] = point
    }

    return normalizedIntradayPoints(Array(merged.values), marketOpen: marketOpen)
}

private func normalizedIntradayPoints(
    _ points: [IntradayPricePoint],
    marketOpen _: Bool
) -> [IntradayPricePoint] {
    points
        .filter { point in
            guard !point.isBlank && point.curPrice > 0 else { return false }
            return point.isRegularTradingMinute
        }
        .sorted {
            guard let lhs = $0.date, let rhs = $1.date else {
                return ($0.openedMins ?? 0) < ($1.openedMins ?? 0)
            }
            return lhs < rhs
        }
}

@MainActor
final class IntradayPriceViewModel: ObservableObject {
    @Published var points: [IntradayPricePoint] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var tradingDate: String?
    @Published var source: String?
    @Published var marketOpen = false
    @Published var summary: IntradayMarketSummary?

    private var task: Task<Void, Never>?
    private var refreshIntervalSeconds: Double = 60
    private var activeSymbol: String?

    func loadCache(symbol: String) {
        guard let latestDate = UserDefaults.standard.string(forKey: latestDateKey(symbol: symbol)),
              let cached = CacheManager.load(
                IntradayMarketCache.self,
                key: cacheKey(symbol: symbol, tradingDate: latestDate)
              ) else {
            return
        }

        apply(cached)
    }

    func fetch(symbol: String) async {
        setLoading(points.isEmpty)
        setErrorMessage(nil)

        guard let url = marketURL(symbol: symbol) else {
            setErrorMessage("URL 错误")
            setLoading(false)
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try await CacheManager.decode(IntradayMarketResponse.self, from: data)

            if result.ok {
                let cache = mergedIntradayCache(
                    IntradayMarketCache(
                    tradingDate: result.tradingDate ?? tradingDate ?? "",
                    source: result.source,
                    marketOpen: result.marketOpen ?? false,
                    refreshIntervalSeconds: result.refreshIntervalSeconds ?? 60,
                    points: normalized(
                        result.points(for: symbol),
                        marketOpen: result.marketOpen ?? false
                    ),
                    summary: result.summary(for: symbol)
                    ),
                    symbol: symbol
                )

                guard !cache.tradingDate.isEmpty else {
                    setLoading(false)
                    return
                }

                await save(cache, symbol: symbol)
                apply(cache)
            } else {
                setErrorMessage(result.error)
            }
        } catch {
            setErrorMessage(error.localizedDescription)
            loadCache(symbol: symbol)
        }

        setLoading(false)
    }

    func start(symbol: String) {
        guard task == nil || activeSymbol != symbol else { return }

        task?.cancel()
        activeSymbol = symbol

        task = Task {
            while !Task.isCancelled {
                await fetch(symbol: symbol)

                try? await Task.sleep(
                    nanoseconds: UInt64(refreshIntervalSeconds * 1_000_000_000)
                )
            }
        }
    }

    func resetForOpenSession(symbol: String) {
        guard activeSymbol == nil || activeSymbol == symbol else { return }

        marketOpen = true

        Task {
            await fetch(symbol: symbol)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        activeSymbol = nil
    }

    private func apply(_ cache: IntradayMarketCache) {
        let normalizedPoints = normalized(cache.points, marketOpen: cache.marketOpen)

        if tradingDate != cache.tradingDate {
            tradingDate = cache.tradingDate
        }
        if source != cache.source {
            source = cache.source
        }
        if marketOpen != cache.marketOpen {
            marketOpen = cache.marketOpen
        }
        refreshIntervalSeconds = max(cache.refreshIntervalSeconds, 1)
        if points != normalizedPoints {
            points = normalizedPoints
        }
        if summary != cache.summary {
            summary = cache.summary
        }
    }

    private func setLoading(_ newValue: Bool) {
        guard isLoading != newValue else { return }
        isLoading = newValue
    }

    private func setErrorMessage(_ newValue: String?) {
        guard errorMessage != newValue else { return }
        errorMessage = newValue
    }

    private func save(_ cache: IntradayMarketCache, symbol: String) async {
        await saveIntradayCache(cache, symbol: symbol)
    }

    private func cacheKey(symbol: String, tradingDate: String) -> String {
        "intraday_market_\(normalizedSymbolKey(symbol))_\(tradingDate)"
    }

    private func latestDateKey(symbol: String) -> String {
        "intraday_market_\(normalizedSymbolKey(symbol))_latest_date"
    }

    private func cachedDatesKey(symbol: String) -> String {
        "intraday_market_\(normalizedSymbolKey(symbol))_cached_dates"
    }

    private func normalizedSymbolKey(_ symbol: String) -> String {
        symbol
            .uppercased()
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }

    private func marketURL(symbol: String) -> URL? {
        BackendConfig.url(
            path: "market",
            queryItems: [URLQueryItem(name: "symbol", value: symbol)]
        )
    }

    private func normalized(
        _ points: [IntradayPricePoint],
        marketOpen: Bool
    ) -> [IntradayPricePoint] {
        normalizedIntradayPoints(points, marketOpen: marketOpen)
    }
}

struct IntradayLineChart: View {
    let symbol: String
    @ObservedObject var marketVM: MarketStatusViewModel
    var height: CGFloat = 58
    var refreshesOnAppear = true
    var maximumPointCount: Int?
    var initialRefreshDelay: Double = 0

    @StateObject private var vm = IntradayPriceViewModel()

    var body: some View {
        IntradaySparklineChart(
            points: vm.points,
            height: height,
            maximumPointCount: maximumPointCount
        )
            .overlay {
                if vm.points.isEmpty && refreshesOnAppear {
                    ProgressView()
                        .opacity(vm.isLoading ? 1 : 0)
                }
            }
            .task(id: symbol) {
                vm.loadCache(symbol: symbol)

                if refreshesOnAppear {
                    if initialRefreshDelay > 0 {
                        try? await Task.sleep(for: .seconds(initialRefreshDelay))
                        guard !Task.isCancelled else { return }
                    }
                    vm.start(symbol: symbol)
                }
            }
            .onChange(of: marketVM.session) { oldSession, newSession in
                guard oldSession != .regular, newSession == .regular else { return }
                vm.resetForOpenSession(symbol: symbol)
            }
            .onDisappear {
                vm.stop()
            }
    }

}

struct IntradaySparklineChart: View {
    let points: [IntradayPricePoint]
    var height: CGFloat = 58
    var maximumPointCount: Int?
    var tintColor: Color?

    private var renderedPoints: [IntradayPricePoint] {
        guard let maximumPointCount,
              maximumPointCount > 2,
              points.count > maximumPointCount else {
            return points
        }

        let step = Double(points.count - 1) / Double(maximumPointCount - 1)
        var indices = Set<Int>()

        for offset in 0..<maximumPointCount {
            indices.insert(Int((Double(offset) * step).rounded()))
        }

        return indices.sorted().map { points[$0] }
    }

    private var lineColor: Color {
        if let tintColor {
            return tintColor
        }

        guard let first = renderedPoints.first?.curPrice,
              let last = renderedPoints.last?.curPrice else {
            return .secondary
        }

        return last >= first ? .green : .red
    }

    private var yDomain: ClosedRange<Double> {
        let prices = renderedPoints.map(\.curPrice)
        guard let minPrice = prices.min(),
              let maxPrice = prices.max() else {
            return 0...1
        }

        guard minPrice != maxPrice else {
            let padding = max(abs(minPrice) * 0.002, 0.01)
            return (minPrice - padding)...(maxPrice + padding)
        }

        let padding = max((maxPrice - minPrice) * 0.08, 0.01)
        return (minPrice - padding)...(maxPrice + padding)
    }

    private var minPrice: Double {
        renderedPoints.map(\.curPrice).min() ?? 0
    }

    var body: some View {
        Chart(renderedPoints) { point in
            if let date = point.date {
                LineMark(
                    x: .value("Time", date),
                    y: .value("Price", point.curPrice)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(lineColor)
                .lineStyle(StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

                AreaMark(
                    x: .value("Time", date),
                    yStart: .value("Min", minPrice),
                    yEnd: .value("Price", point.curPrice)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            lineColor.opacity(0.3),
                            .clear
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
        .frame(height: height)
    }
}
