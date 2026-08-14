//
//  QuoteViewModel.swift
//  PortSight
//
//  Created by Chris Cui on 30/4/2026.
//


import Foundation
import Combine

struct QuoteResponse: Codable {
    let ok: Bool
    let code: String?
    let name: String?
    let price: Double?
    let open_price: Double?
    let high_price: Double?
    let low_price: Double?
    let prev_close_price: Double?
    let change: Double?
    let change_percent: Double?
    let data_date: String?
    let data_time: String?
    let error: String?
    let pre_price: Double?
    let after_price: Double?
    let overnight_price: Double?
}


@MainActor
class QuoteViewModel: ObservableObject {
    @Published var quotes: [String: QuoteResponse] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    private var task: Task<Void, Never>?

    private func cacheKey(symbol: String) -> String {
            "quote_cache_\(symbol)"
        }
    func quote(for symbol: String) -> QuoteResponse? {
        quotes[symbol]
    }
    func loadCache(symbol: String) {
        if let cached = CacheManager.load(QuoteResponse.self, key: cacheKey(symbol: symbol)) {
            quotes[symbol] = cached
        }
    }
    func fetchQuote(symbol: String) async {
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

    func loadCaches(symbols: [String]) {
        for symbol in symbols {
            loadCache(symbol: symbol)
        }
    }

    func fetchQuoteValue(symbol: String) async -> QuoteResponse? {
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

    func fetchQuotes(symbols: [String]) async {
        loadCaches(symbols: symbols)
        await refreshQuotes(symbols: symbols)
    }

    func refreshQuotes(symbols: [String]) async {
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
    
    func startPolling(symbol: String, marketVM: MarketStatusViewModel) {
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
    func stopPolling() {
        task?.cancel()
        task = nil
    }
}
