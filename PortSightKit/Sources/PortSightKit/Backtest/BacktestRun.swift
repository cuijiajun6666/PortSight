//
//  BacktestRun.swift
//  PortSight
//
//  A backtest run: its meta, and its trades, equity, bars and signals read when first needed. An exported run
//  (a folder from the quant system) keeps only meta.json in memory until it is selected; trades.json and
//  equity.json are read then, and each bar or signal file when it is first shown, off the main thread (a 15m bar
//  file is ~10 MB per symbol). Reading is the only thing it does: no file in the quant system is ever written.
//
//  Forward seal: crypto data from 2026-10-22 on is still sealed, so its trades, equity and signals are dropped
//  here even if an export ever contained them (the quant system should already leave them out).
//

import Foundation

public final class BacktestRun: Identifiable {
    public static let sealStart = Date(timeIntervalSince1970: 1_792_627_200) // 2026-10-22 00:00 UTC

    public let meta: BacktestMeta
    /// Where it was read from; nil for the built-in sample.
    public let directory: URL?

    public var id: String { meta.runID }

    private typealias Contents = (trades: [BacktestTrade], equity: [BacktestEquityPoint], skipped: Int)

    private enum BarStore {
        /// The built-in sample: bars made in memory.
        case memory((String, BacktestTimeframe) -> [BacktestBar], (String) -> [BacktestSignalPoint])
        /// An exported run: bars/<SYMBOL>_<TF>.json and signals/<SYMBOL>.json under the run folder.
        case files(URL)
    }

    private let contentSource: () throws -> Contents
    private var contents: Contents?
    private let store: BarStore
    private let givenSymbols: [String]?

    /// Why trades.json or equity.json could not be read (the run then shows no trades).
    public private(set) var loadError: String?

    private var barCache: [String: [BacktestBar]] = [:]
    private var barOrder: [String] = []
    private var barTasks: [String: Task<[BacktestBar], Never>] = [:]
    private var signalCache: [String: [BacktestSignalPoint]] = [:]
    private var signalTasks: [String: Task<[BacktestSignalPoint], Never>] = [:]
    /// Bar files kept in memory at once (a 15m file is ~140k bars).
    private static let barCacheLimit = 12

    /// A run already in memory (the built-in sample, tests).
    public init(meta: BacktestMeta, trades: [BacktestTrade], equity: [BacktestEquityPoint], symbols: [String],
                directory: URL? = nil,
                bars: @escaping (String, BacktestTimeframe) -> [BacktestBar],
                signals: @escaping (String) -> [BacktestSignalPoint]) {
        self.meta = meta
        self.directory = directory
        givenSymbols = symbols
        contentSource = { (trades, equity, 0) }
        let sealMs = Self.sealStart.milliseconds
        store = .memory(bars, { symbol in signals(symbol).filter { $0.t < sealMs } })
    }

    /// An exported run folder whose meta.json has been read; the rest is read when first needed.
    init(meta: BacktestMeta, folder: URL) {
        self.meta = meta
        directory = folder
        givenSymbols = nil
        store = .files(folder)
        contentSource = {
            let trades: LossyArray<BacktestTrade> = try BacktestLoader.decode("trades.json", in: folder)
            let equity: LossyArray<BacktestEquityPoint> = try BacktestLoader.decode("equity.json", in: folder)
            return (trades.items, equity.items, trades.skipped)
        }
    }

    // MARK: Trades and equity

    private var loaded: Contents {
        if let contents { return contents }
        let sealMs = Self.sealStart.milliseconds
        var result: Contents
        do {
            result = try contentSource()
        } catch {
            loadError = error.localizedDescription
            result = ([], [], 0)
        }
        result.trades = result.trades.filter { $0.entryT < sealMs && $0.exitT < sealMs }.sorted { $0.entryT < $1.entryT }
        result.equity = Self.withDrawdown(result.equity.filter { $0.t < sealMs }.sorted { $0.t < $1.t })
        contents = result
        return result
    }

    /// Whether trades.json and equity.json have been read yet.
    public var isLoaded: Bool { contents != nil }
    public var trades: [BacktestTrade] { loaded.trades }
    public var equity: [BacktestEquityPoint] { loaded.equity }
    /// Trades in trades.json that could not be read at all (no id, symbol or entry time).
    public var skippedTrades: Int { loaded.skipped }

    /// Every symbol, the most traded first, then symbols the export has bars for but never traded.
    public lazy var symbols: [String] = {
        let counts = tradeCounts
        var order: [String] = givenSymbols ?? []
        var listed = Set(order)
        for trade in trades where !listed.contains(trade.symbol) {
            order.append(trade.symbol)
            listed.insert(trade.symbol)
        }
        // Stable: equal counts keep the given (or first-traded) order.
        let traded = order.enumerated().sorted { a, b in
            let ca = counts[a.element] ?? 0, cb = counts[b.element] ?? 0
            return ca != cb ? ca > cb : a.offset < b.offset
        }.map(\.element)
        guard case .files = store else { return traded }
        let known = Set(traded)
        return traded + barFiles.keys.filter { !known.contains($0) }.sorted()
    }()

    /// Trade count per symbol.
    public lazy var tradeCounts: [String: Int] = Dictionary(grouping: trades, by: \.symbol).mapValues(\.count)

    public func trades(for symbol: String?) -> [BacktestTrade] {
        guard let symbol else { return trades }
        return trades.filter { $0.symbol == symbol }
    }

    public lazy var metrics = BacktestMetrics(trades: trades, equity: equity)

    /// Median holding time of the run's trades, in hours (0 without trades).
    public lazy var medianHoldHours: Double = {
        let holds = trades.map { max($0.holdH, ($0.exitT - $0.entryT) / 3_600_000) }.sorted()
        return holds.isEmpty ? 0 : holds[holds.count / 2]
    }()

    /// The drawdown column recomputed from NAV when the export left it out.
    private static func withDrawdown(_ equity: [BacktestEquityPoint]) -> [BacktestEquityPoint] {
        guard equity.contains(where: { !$0.dd.isFinite }) else { return equity }
        var peak = 0.0
        return equity.map { point in
            peak = max(peak, point.nav)
            return BacktestEquityPoint(t: point.t, nav: point.nav, dd: peak > 0 ? point.nav / peak - 1 : 0, benchNav: point.benchNav)
        }
    }

    // MARK: Bars and signals

    /// Bar files per symbol, from the bars/ folder listing (no file is read for this).
    private lazy var barFiles: [String: Set<BacktestTimeframe>] = {
        guard case .files(let folder) = store else { return [:] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "bars").path())) ?? []
        var files: [String: Set<BacktestTimeframe>] = [:]
        for name in names where name.hasSuffix(".json") {
            let stem = name.dropLast(5)
            guard let split = stem.lastIndex(of: "_"), let timeframe = BacktestTimeframe(rawValue: String(stem[stem.index(after: split)...])) else { continue }
            let symbol = String(stem[..<split])
            if !symbol.isEmpty { files[symbol, default: []].insert(timeframe) }
        }
        return files
    }()

    private func barsURL(_ symbol: String, _ timeframe: BacktestTimeframe) -> URL? {
        guard case .files(let folder) = store, barFiles[symbol]?.contains(timeframe) == true else { return nil }
        return folder.appending(path: "bars/\(symbol)_\(timeframe.rawValue).json")
    }

    /// Timeframes the export has bars for, for this symbol, shortest first.
    public func timeframes(_ symbol: String) -> [BacktestTimeframe] {
        switch store {
        case .files: BacktestTimeframe.allCases.filter { barFiles[symbol]?.contains($0) == true }
        case .memory: BacktestTimeframe.allCases.filter { !bars(symbol, $0).isEmpty }
        }
    }

    /// Bars already in memory; nil while an exported file has not been read yet (see `loadBars`).
    public func cachedBars(_ symbol: String, _ timeframe: BacktestTimeframe) -> [BacktestBar]? {
        if case .memory = store { return bars(symbol, timeframe) }
        guard barsURL(symbol, timeframe) != nil else { return [] }
        return barCache[symbol + "_" + timeframe.rawValue]
    }

    /// Bars for one symbol and timeframe, oldest first (empty when the export has none). Reads the file on the
    /// calling thread when it is not in memory yet; prefer `loadBars` for exported runs.
    public func bars(_ symbol: String, _ timeframe: BacktestTimeframe) -> [BacktestBar] {
        let key = symbol + "_" + timeframe.rawValue
        if let cached = barCache[key] { return cached }
        let loaded: [BacktestBar]
        switch store {
        case .memory(let source, _): loaded = source(symbol, timeframe).sorted { $0.t < $1.t }
        case .files:
            guard let url = barsURL(symbol, timeframe) else { return [] }
            loaded = BacktestFileReader.bars(at: url)
        }
        remember(loaded, key)
        return loaded
    }

    /// Reads a bar file off the main thread (once, however many callers ask), then keeps it in memory.
    public func loadBars(_ symbol: String, _ timeframe: BacktestTimeframe) async -> [BacktestBar] {
        if let cached = cachedBars(symbol, timeframe) { return cached }
        let key = symbol + "_" + timeframe.rawValue
        if let task = barTasks[key] { return await task.value }
        guard let url = barsURL(symbol, timeframe) else { return [] }
        let task = Task.detached(priority: .userInitiated) { BacktestFileReader.bars(at: url) }
        barTasks[key] = task
        let loaded = await task.value
        barTasks[key] = nil
        remember(loaded, key)
        return loaded
    }

    /// Whether a bar file is being read right now.
    public func isLoadingBars(_ symbol: String, _ timeframe: BacktestTimeframe) -> Bool {
        barTasks[symbol + "_" + timeframe.rawValue] != nil
    }

    private func remember(_ bars: [BacktestBar], _ key: String) {
        barCache[key] = bars
        barOrder.removeAll { $0 == key }
        barOrder.append(key)
        while barOrder.count > Self.barCacheLimit { barCache[barOrder.removeFirst()] = nil }
    }

    /// Signals already in memory; nil while an exported file has not been read yet (see `loadSignals`).
    public func cachedSignals(_ symbol: String) -> [BacktestSignalPoint]? {
        if case .memory = store { return signals(symbol) }
        return signalCache[symbol]
    }

    /// Signals for one symbol, oldest first. Reads the file on the calling thread when not in memory yet.
    public func signals(_ symbol: String) -> [BacktestSignalPoint] {
        if let cached = signalCache[symbol] { return cached }
        let loaded: [BacktestSignalPoint]
        switch store {
        case .memory(_, let source): loaded = source(symbol).sorted { $0.t < $1.t }
        case .files(let folder): loaded = BacktestFileReader.signals(at: folder.appending(path: "signals/\(symbol).json"))
        }
        signalCache[symbol] = loaded
        return loaded
    }

    /// Reads a signal file off the main thread.
    public func loadSignals(_ symbol: String) async -> [BacktestSignalPoint] {
        if let cached = cachedSignals(symbol) { return cached }
        if let task = signalTasks[symbol] { return await task.value }
        guard case .files(let folder) = store else { return signals(symbol) }
        let url = folder.appending(path: "signals/\(symbol).json")
        let task = Task.detached(priority: .utility) { BacktestFileReader.signals(at: url) }
        signalTasks[symbol] = task
        let loaded = await task.value
        signalTasks[symbol] = nil
        signalCache[symbol] = loaded
        return loaded
    }
}

// MARK: - Reading exported folders

public enum BacktestLoader {
    public enum LoadError: LocalizedError {
        case missing(String)
        case unreadable(String, Error)
        case noRuns

        public var errorDescription: String? {
            switch self {
            case .missing(let file): "目录里没有 \(file)"
            case .unreadable(let file, let error): "\(file) 读不出来：\(Self.describe(error))"
            case .noRuns: "这个目录里没有回测：既不是单个回测目录（meta.json），也没有 index.json 或带 meta.json 的子目录"
            }
        }

        private static func describe(_ error: Error) -> String {
            guard let decoding = error as? DecodingError else { return error.localizedDescription }
            switch decoding {
            case .keyNotFound(let key, let context): return "缺少 \(key.stringValue)（\(path(context))）"
            case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
                return context.debugDescription + "（\(path(context))）"
            @unknown default: return error.localizedDescription
            }
        }

        private static func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map { "#\($0)" } ?? $0.stringValue }.joined(separator: ".")
        }
    }

    /// One exported run folder: meta.json now, trades.json and equity.json when the run is first shown, bars and
    /// signals when first drawn.
    public static func load(directory: URL) throws -> BacktestRun {
        let meta: BacktestMeta = try decode("meta.json", in: directory)
        for file in ["trades.json", "equity.json"] where !exists(file, in: directory) { throw LoadError.missing(file) }
        return BacktestRun(meta: meta, folder: directory)
    }

    /// A single run folder (it has meta.json), or a folder of runs: the ones index.json lists, in its order, or
    /// else every subfolder with a meta.json. Runs that cannot be read are skipped; `failures` names them.
    public static func loadAll(from directory: URL) throws -> (runs: [BacktestRun], failures: [String]) {
        if exists("meta.json", in: directory) { return ([try load(directory: directory)], []) }
        let folders = runFolders(in: directory)
        guard !folders.isEmpty else { throw LoadError.noRuns }
        var runs: [BacktestRun] = [], failures: [String] = []
        for folder in folders {
            do { runs.append(try load(directory: folder)) } catch {
                failures.append(folder.lastPathComponent + "：" + error.localizedDescription)
            }
        }
        if runs.isEmpty, let first = failures.first { throw LoadError.unreadable(first, LoadError.noRuns) }
        return (runs, failures)
    }

    /// Whether a folder holds several runs (index.json, or subfolders with meta.json) rather than being one.
    public static func isRunCollection(_ directory: URL) -> Bool {
        !exists("meta.json", in: directory) && !runFolders(in: directory).isEmpty
    }

    static func runFolders(in root: URL) -> [URL] {
        struct Index: Decodable { let runs: [String] }
        if let index: Index = try? decode("index.json", in: root) {
            let listed = index.runs.map { root.appending(path: $0, directoryHint: .isDirectory) }.filter { exists("meta.json", in: $0) }
            if !listed.isEmpty { return listed }
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path())) ?? []
        return names.filter { !$0.hasPrefix("_") && !$0.hasPrefix(".") }.sorted()
            .map { root.appending(path: $0, directoryHint: .isDirectory) }
            .filter { exists("meta.json", in: $0) }
    }

    static func exists(_ file: String, in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: file).path())
    }

    static func decode<T: Decodable>(_ file: String, in directory: URL) throws -> T {
        let url = directory.appending(path: file)
        guard FileManager.default.fileExists(atPath: url.path()) else { throw LoadError.missing(file) }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url, options: .mappedIfSafe))
        } catch {
            throw LoadError.unreadable(file, error)
        }
    }
}

/// Bar and signal files, read with JSONSerialization (several times faster than JSONDecoder on 10 MB of bars)
/// and off the main thread. Rows with a missing or non-numeric price are skipped.
nonisolated enum BacktestFileReader {
    static func bars(at url: URL) -> [BacktestBar] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        var bars: [BacktestBar] = []
        bars.reserveCapacity(rows.count)
        var sorted = true
        for row in rows {
            guard let t = number(row["t"]), let o = number(row["o"]), let h = number(row["h"]),
                  let l = number(row["l"]), let c = number(row["c"]) else { continue }
            if let last = bars.last, last.t > t { sorted = false }
            bars.append(BacktestBar(t: t, o: o, h: h, l: l, c: c, v: number(row["v"]) ?? 0))
        }
        if !sorted { bars.sort { $0.t < $1.t } }
        return bars
    }

    static func signals(at url: URL) -> [BacktestSignalPoint] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        let sealMs = 1_792_627_200_000.0 // BacktestRun.sealStart
        var points: [BacktestSignalPoint] = []
        points.reserveCapacity(rows.count)
        for row in rows {
            guard let t = number(row["t"]), t < sealMs else { continue }
            var values: [String: Double] = [:]
            for (key, value) in row where key != "t" {
                if let number = number(value) { values[key] = number }
            }
            points.append(BacktestSignalPoint(t: t, values: values))
        }
        points.sort { $0.t < $1.t }
        return points
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }
}
