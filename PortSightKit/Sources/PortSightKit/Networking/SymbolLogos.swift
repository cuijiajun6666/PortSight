//
//  SymbolLogos.swift
//  PortSightKit
//
//  Real icons for stocks, ETFs and coins, shared by the iOS and Mac apps: logo.dev's ticker logos
//  (img.logo.dev/ticker/AAPL) and crypto logos (img.logo.dev/crypto/btc), with the app's publishable key. Each icon is
//  fetched once and kept in Application Support (PortSight/logos, not purged like Caches): only a new asset is ever
//  downloaded. A symbol logo.dev does not know answers 404 (fallback=404), keeps the letter placeholder and is not
//  asked again for a week (remembered on disk too); a fetch that failed on the network is retried after an hour.
//  Currency pairs (AUD.USD) and empty symbols are never asked for. These requests are the one exception besides the
//  relay that DemoOfflineProtocol lets through.
//

import Foundation
import ImageIO
import Observation

@Observable
public final class SymbolLogoStore {
    public static let shared = SymbolLogoStore()

    /// logo.dev publishable key (meant to be shipped in clients; it only serves images).
    public static let publicKey = "pk_SqIJPzG-Swq_mcIu-urXVA"
    public static let host = "img.logo.dev"

    /// PNG data per key (see `key`).
    public private(set) var images: [String: Data] = [:]

    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var failedAt: [String: Date] = [:]
    @ObservationIgnored private let directory: URL?
    @ObservationIgnored private let fetch: (URL) async throws -> (Data, Int)

    public init(directory: URL? = SymbolLogoStore.defaultDirectory,
                fetch: ((URL) async throws -> (Data, Int))? = nil) {
        self.directory = directory
        self.fetch = fetch ?? { url in
            let (data, response) = try await URLSession.shared.data(from: url)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        restore()
    }

    public static var defaultDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PortSight/logos", isDirectory: true)
    }

    /// logo.dev has no icon for these (404): not asked again before a week has passed.
    @ObservationIgnored private var missing: [String: Date] = [:]
    static let missingFor: TimeInterval = 7 * 24 * 3_600

    // MARK: Reading

    /// The icon of `symbol` if it is here already (start `load` to fetch it).
    public func image(_ symbol: String, crypto: Bool) -> Data? {
        Self.key(symbol, crypto: crypto).flatMap { images[$0] }
    }

    /// Fetches the icon unless it is here, being fetched, or failed within the last hour.
    public func load(_ symbol: String, crypto: Bool) async {
        guard let key = Self.key(symbol, crypto: crypto), images[key] == nil, !inFlight.contains(key),
              let url = Self.url(symbol, crypto: crypto) else { return }
        if let failed = failedAt[key], Date.now.timeIntervalSince(failed) < 3_600 { return }
        if let gone = missing[key], Date.now.timeIntervalSince(gone) < Self.missingFor { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        do {
            let (data, status) = try await fetch(url)
            guard status == 200, Self.isImage(data) else {
                if status == 404 {
                    missing[key] = .now
                    saveMissing()
                } else {
                    failedAt[key] = .now
                }
                return
            }
            images[key] = data
            save(data, key: key)
        } catch {
            if !RelayAPI.isCancellation(error) { failedAt[key] = .now }
        }
    }

    /// Keeps exactly the icons of `symbols` on this device: downloads the new ones (one at a time) and deletes the
    /// ones no longer needed (an asset that is gone). Everything else stays as it is: nothing is downloaded twice.
    public func sync(_ symbols: [(symbol: String, crypto: Bool)]) async {
        var wanted: [String: (symbol: String, crypto: Bool)] = [:]
        for item in symbols {
            if let key = Self.key(item.symbol, crypto: item.crypto), wanted[key] == nil { wanted[key] = item }
        }
        guard !wanted.isEmpty else { return }  // nothing known yet: never wipe the icons
        for key in Array(images.keys) where wanted[key] == nil {
            images[key] = nil
            if let directory { try? FileManager.default.removeItem(at: directory.appendingPathComponent(key + ".png")) }
        }
        let gone = missing.keys.filter { wanted[$0] == nil }
        if !gone.isEmpty {
            for key in gone { missing[key] = nil }
            saveMissing()
        }
        for (key, item) in wanted.sorted(by: { $0.key < $1.key }) where images[key] == nil {
            await load(item.symbol, crypto: item.crypto)
        }
    }

    /// The icons the app shows: every holding (real and built in), every symbol in the IBKR activity (sold assets
    /// still appear in orders), and the market heatmap's.
    public static func symbolsInUse() -> [(symbol: String, crypto: Bool)] {
        var result: [(symbol: String, crypto: Bool)] = []
        for holding in Portfolio.combined(.all) {
            result.append((holding.symbol, isCrypto(holding.symbol, kind: holding.kind)))
        }
        for item in IBKRActivityStore.shared.items {
            guard let symbol = item.symbol, item.kind == .fill || item.kind == .order || item.kind == .position else { continue }
            result.append((symbol, item.sec_type?.uppercased() == "CRYPTO" || isCrypto(symbol)))
        }
        for stock in DemoMarketHeatmap.stocks { result.append((stock.symbol, false)) }
        return result
    }

    // MARK: Keys and URLs

    /// "stock_AAPL" / "crypto_BTC"; nil for something with no icon (a currency pair, nothing).
    public static func key(_ symbol: String, crypto: Bool) -> String? {
        guard let ticker = ticker(symbol, crypto: crypto) else { return nil }
        return (crypto ? "crypto_" : "stock_") + ticker
    }

    /// Currency codes: alone ("USD") or as a pair ("AUD.USD") they are cash, not a stock, and get no logo (logo.dev
    /// would answer with an unrelated fund that has the same ticker).
    static let currencies: Set<String> = ["USD", "AUD", "EUR", "GBP", "JPY", "CNH", "CNY", "HKD", "CAD", "CHF", "SGD",
                                          "NZD", "SEK", "NOK", "DKK", "KRW", "INR", "MXN", "ZAR", "TWD"]

    /// "AUD.USD", "AUD/USD" or a bare "USD": a currency (shown with an exchange symbol instead of a logo).
    public static func isCurrency(_ symbol: String) -> Bool {
        let text = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if currencies.contains(text) { return true }
        let parts = text.split(whereSeparator: { $0 == "." || $0 == "/" }).map(String.init)
        return parts.count == 2 && parts.allSatisfy { currencies.contains($0) }
    }

    /// "US.AAPL" → "AAPL", "HK.00700" → "00700"; anything else (a currency pair "AUD.USD") as it is, uppercased.
    public static func displayTicker(_ symbol: String) -> String {
        var text = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        for prefix in ["US.", "HK.", "SH.", "SZ."] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        return text
    }

    /// "US.AAPL" → "AAPL", "BTC-USDT" → "BTC"; nil for "AUD.USD", "USD" or "".
    static func ticker(_ symbol: String, crypto: Bool) -> String? {
        guard crypto || !isCurrency(symbol) else { return nil }
        var text = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        for prefix in ["US.", "HK.", "SH.", "SZ."] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        if crypto, let base = text.split(whereSeparator: { $0 == "-" || $0 == "/" }).first { text = String(base) }
        guard !text.isEmpty, !text.contains("."), !text.contains(" "),
              text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        return text
    }

    public static func url(_ symbol: String, crypto: Bool, size: Int = 128) -> URL? {
        guard let ticker = ticker(symbol, crypto: crypto) else { return nil }
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = host
        parts.path = crypto ? "/crypto/" + ticker.lowercased() : "/ticker/" + ticker
        parts.queryItems = [
            URLQueryItem(name: "token", value: publicKey),
            URLQueryItem(name: "size", value: String(size)),
            URLQueryItem(name: "format", value: "png"),
            URLQueryItem(name: "retina", value: "true"),
            URLQueryItem(name: "fallback", value: "404"),
        ]
        return parts.url
    }

    /// A coin rather than a stock / ETF: the holding's kind says so, or the symbol is a well-known coin or a USDT pair.
    public static func isCrypto(_ symbol: String, kind: String? = nil) -> Bool {
        if kind == "加密货币" { return true }
        let text = symbol.uppercased()
        if text.hasSuffix("-USDT") || text.hasSuffix("-USD") || text.hasSuffix("/USDT") { return true }
        return knownCoins.contains(text)
    }

    static let knownCoins: Set<String> = ["BTC", "ETH", "SOL", "BNB", "XRP", "DOGE", "ADA", "AVAX", "TON", "TRX", "DOT",
                                         "LINK", "LTC", "BCH", "UNI", "ATOM", "NEAR", "APT", "ARB", "OP", "SUI", "HYPE",
                                         "USDT", "USDC", "PEPE", "SHIB", "XLM", "FIL", "ETC", "INJ"]

    /// A request for an icon (let through by DemoOfflineProtocol).
    public static func isLogoRequest(_ request: URLRequest) -> Bool {
        request.url?.scheme == "https" && request.url?.host == host
    }

    static func isImage(_ data: Data) -> Bool {
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    // MARK: Disk

    private func save(_ data: Data, key: String) {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(key + ".png"), options: .atomic)
    }

    private var missingURL: URL? { directory?.appendingPathComponent("missing.json") }

    private func saveMissing() {
        guard let directory, let url = missingURL, let data = try? JSONEncoder().encode(missing) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func restore() {
        if let url = missingURL, let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: Date].self, from: data) {
            missing = saved
        }
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "png" {
            if let data = try? Data(contentsOf: file), Self.isImage(data) {
                images[file.deletingPathExtension().lastPathComponent] = data
            }
        }
    }
}
