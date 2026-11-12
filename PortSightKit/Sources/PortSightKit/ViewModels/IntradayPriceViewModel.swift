import Foundation
import Combine
public func loadCachedIntradaySparklinePrices(
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

public func fetchIntradaySparklinePrices(
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
public final class IntradayPriceViewModel: ObservableObject {
    @Published public var points: [IntradayPricePoint] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var tradingDate: String?
    @Published public var source: String?
    @Published public var marketOpen = false
    @Published public var summary: IntradayMarketSummary?

    private var task: Task<Void, Never>?
    private var refreshIntervalSeconds: Double = 60
    private var activeSymbol: String?

    /// Kept for the pages that ask: no longer set (the built-in curve is drawn whether or not a relay is paired; the
    /// relay has no price history yet).
    @Published public var missingNote: String?

    public func loadDemo(symbol: String) {
        let ticker = symbol.replacingOccurrences(of: "US.", with: "")
        missingNote = nil
        // Each app keeps the demo prices it shipped with, so its existing charts draw exactly as before.
        #if os(iOS)
        // A held symbol's curve ends at its real price once paired (Portfolio.holding), else the built-in one.
        let price = Portfolio.holding(ticker)?.price ?? DemoPortfolioData.holdings.first { $0.symbol == ticker }?.price ?? (ticker == "IXIC" ? 18240 : 5314)
        #else
        let indexPrices: [String: Double] = ["IXIC": 18240, "SPX": 5314, "DJI": 39284]
        let price = Portfolio.holding(ticker)?.price ?? DemoPortfolioData.holdings.first { $0.symbol == ticker }?.price ?? indexPrices[ticker] ?? 100
        #endif
        points = (0..<48).map { index in
            let value = price * (0.985 + Double(index) * 0.00032 + sin(Double(index) * 0.55) * 0.0018)
            return IntradayPricePoint(code: symbol, time: String(format: "2026-10-23 %02d:%02d:00", 9 + (30 + index * 5) / 60, (30 + index * 5) % 60),
                openedMins: 570 + index * 5, curPrice: value, lastClose: price * 0.985)
        }
        let last = points.last!.curPrice, previous = price * 0.985
        summary = IntradayMarketSummary(code: symbol, chartCode: symbol, quoteCode: symbol, name: ticker,
            price: last, previousClose: previous, change: last - previous, changePercent: (last / previous - 1) * 100,
            latestTime: "2026-10-23 13:25:00", points: points.count, quoteError: nil)
        source = "demo"; tradingDate = "2026-10-23"; marketOpen = false; isLoading = false
    }

    public func loadCache(symbol: String) {
        if DemoPortfolioData.enabled { loadDemo(symbol: symbol); return }
        guard let latestDate = UserDefaults.standard.string(forKey: latestDateKey(symbol: symbol)),
              let cached = CacheManager.load(
                IntradayMarketCache.self,
                key: cacheKey(symbol: symbol, tradingDate: latestDate)
              ) else {
            return
        }

        apply(cached)
    }

    public func fetch(symbol: String) async {
        if DemoPortfolioData.enabled { loadDemo(symbol: symbol); return }
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

    public func start(symbol: String) {
        if DemoPortfolioData.enabled { loadDemo(symbol: symbol); return }
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

    public func resetForOpenSession(symbol: String) {
        guard activeSymbol == nil || activeSymbol == symbol else { return }

        marketOpen = true

        Task {
            await fetch(symbol: symbol)
        }
    }

    public func stop() {
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

    public init() {}
}

