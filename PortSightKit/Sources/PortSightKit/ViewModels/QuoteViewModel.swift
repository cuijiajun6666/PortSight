//
//  QuoteViewModel.swift
//  PortSight
//
//  Created by Chris Cui on 30/4/2026.
//


import Foundation
import Combine

public struct QuoteResponse: Codable {
    public let ok: Bool
    public let code: String?
    public let name: String?
    public let price: Double?
    public let open_price: Double?
    public let high_price: Double?
    public let low_price: Double?
    public let prev_close_price: Double?
    public let change: Double?
    public let change_percent: Double?
    public let data_date: String?
    public let data_time: String?
    public let error: String?
    public let pre_price: Double?
    public let after_price: Double?
    public let overnight_price: Double?

    public init(ok: Bool, code: String?, name: String?, price: Double?, open_price: Double?, high_price: Double?, low_price: Double?, prev_close_price: Double?, change: Double?, change_percent: Double?, data_date: String?, data_time: String?, error: String?, pre_price: Double?, after_price: Double?, overnight_price: Double?) {
        self.ok = ok
        self.code = code
        self.name = name
        self.price = price
        self.open_price = open_price
        self.high_price = high_price
        self.low_price = low_price
        self.prev_close_price = prev_close_price
        self.change = change
        self.change_percent = change_percent
        self.data_date = data_date
        self.data_time = data_time
        self.error = error
        self.pre_price = pre_price
        self.after_price = after_price
        self.overnight_price = overnight_price
    }
}


@MainActor
public class QuoteViewModel: ObservableObject {
    @Published public var quotes: [String: QuoteResponse] = [:]
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    private var task: Task<Void, Never>?

    /// Before pairing, the built-in quote. Once paired, a symbol held for real has IBKR's price (market value per
    /// share, yesterday's close from today's P&L); anything else keeps the built-in quote.
    private func demoQuote(_ symbol: String) -> QuoteResponse? {
        let ticker = symbol.replacingOccurrences(of: "US.", with: "")
        if Portfolio.isLive, let holding = Portfolio.holding(ticker), holding.price > 0 {
            let price = holding.price, previous = holding.previous > 0 ? holding.previous : holding.price
            return QuoteResponse(ok: true, code: symbol, name: holding.name, price: price, open_price: nil, high_price: nil,
                low_price: nil, prev_close_price: previous, change: price - previous,
                change_percent: (price / previous - 1) * 100, data_date: nil, data_time: nil, error: nil,
                pre_price: nil, after_price: nil, overnight_price: nil)
        }
        let holding = DemoPortfolioData.holdings.first { $0.symbol == ticker }
        let price = holding?.price ?? 100, previous = holding?.previous ?? 98
        return QuoteResponse(ok: true, code: symbol, name: holding?.name ?? symbol, price: price,
            open_price: previous, high_price: price * 1.01, low_price: previous * 0.995,
            prev_close_price: previous, change: price - previous, change_percent: (price / previous - 1) * 100,
            data_date: "2026-10-23", data_time: "16:00:00", error: nil, pre_price: nil, after_price: nil, overnight_price: nil)
    }

    private func cacheKey(symbol: String) -> String {
            "quote_cache_\(symbol)"
        }
    public func quote(for symbol: String) -> QuoteResponse? {
        DemoPortfolioData.enabled ? demoQuote(symbol) : quotes[symbol]
    }
    public func loadCache(symbol: String) {
        if let cached = CacheManager.load(QuoteResponse.self, key: cacheKey(symbol: symbol)) {
            quotes[symbol] = cached
        }
    }
    public func fetchQuote(symbol: String) async {
        if DemoPortfolioData.enabled { quotes[symbol] = demoQuote(symbol); return }
        isLoading = true
        errorMessage = nil
        guard let url = BackendConfig.url(
            path: "quote",
            queryItems: [URLQueryItem(name: "symbol", value: symbol)]
        ) else {
            errorMessage = "URL 错误"
            isLoading = false
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try await CacheManager.decode(QuoteResponse.self, from: data)
            if result.ok {
                quotes[symbol] = result
                await CacheManager.saveAsync(result, key: cacheKey(symbol: symbol))
            } else {
                errorMessage = result.error
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    public func loadCaches(symbols: [String]) {
        for symbol in symbols {
            loadCache(symbol: symbol)
        }
    }

    public func fetchQuoteValue(symbol: String) async -> QuoteResponse? {
        if DemoPortfolioData.enabled { return demoQuote(symbol) }
        guard let url = BackendConfig.url(
            path: "quote",
            queryItems: [URLQueryItem(name: "symbol", value: symbol)]
        ) else {
            errorMessage = "URL 错误"
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try await CacheManager.decode(QuoteResponse.self, from: data)
            guard result.ok else {
                errorMessage = result.error
                return nil
            }

            await CacheManager.saveAsync(result, key: cacheKey(symbol: symbol))
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func fetchQuotes(symbols: [String]) async {
        loadCaches(symbols: symbols)
        await refreshQuotes(symbols: symbols)
    }

    public func refreshQuotes(symbols: [String]) async {
        let uniqueSymbols = Array(Set(symbols)).sorted()
        guard !uniqueSymbols.isEmpty else { return }

        isLoading = quotes.isEmpty
        defer { isLoading = false }

        var refreshedQuotes = quotes

        for batchStart in stride(from: 0, to: uniqueSymbols.count, by: 4) {
            let batch = Array(uniqueSymbols[batchStart..<min(batchStart + 4, uniqueSymbols.count)])

            await withTaskGroup(of: (String, QuoteResponse?).self) { group in
                for symbol in batch {
                    group.addTask {
                        let quote = await self.fetchQuoteValue(symbol: symbol)
                        return (symbol, quote)
                    }
                }

                for await (symbol, quote) in group {
                    if let quote {
                        refreshedQuotes[symbol] = quote
                    }
                }
            }

            guard quotesSignature(quotes) != quotesSignature(refreshedQuotes) else { continue }
            quotes = refreshedQuotes
        }
    }

    private func quotesSignature(_ quotes: [String: QuoteResponse]) -> String {
        quotes.keys.sorted().map { symbol in
            let quote = quotes[symbol]
            return "\(symbol):\(quote?.price ?? 0):\(quote?.change ?? 0):\(quote?.change_percent ?? 0)"
        }.joined(separator: "|")
    }
    
    public func startPolling(symbol: String, marketVM: MarketStatusViewModel) {
        if DemoPortfolioData.enabled { return }
        task?.cancel()

        task = Task {
            while !Task.isCancelled {
                if marketVM.session == .unknown {
                    await marketVM.fetchMarketStatus()
                }

                switch marketVM.session {
                case .regular:
                    await fetchQuote(symbol: symbol)
                    try? await Task.sleep(nanoseconds: 3_000_000_000)

                case .pre, .after, .overnight:
                    await fetchQuote(symbol: symbol)
                    try? await Task.sleep(nanoseconds: 15_000_000_000)

                case .closed, .unknown:
                    // 休市不拉 quote，只隔一段时间检查市场状态
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                }
            }
        }
    }
    public func stopPolling() {
        task?.cancel()
        task = nil
    }

    public init() {}
}
