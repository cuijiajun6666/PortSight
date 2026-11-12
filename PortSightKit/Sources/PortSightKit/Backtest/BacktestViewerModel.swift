//
//  BacktestViewerModel.swift
//  PortSightKit
//
//  Page state for 交易 · 回测, shared by the Mac and iOS viewers: which run (and which to compare), symbol,
//  timeframe, the visible time window of the price chart, the selected trade and the trade list filters.
//  Everything is read-only. Also the geometry of a trade's box on the chart, so both apps draw identical boxes.
//

import Foundation
import Observation

@Observable
public final class BacktestViewerModel: TradeChartModel {
    /// Runs read from exported folders, in the order they were opened (a folder of runs in its index order).
    public private(set) var directoryRuns: [BacktestRun] = []
    /// The built-in sample runs, listed after the exported ones.
    public let sampleRuns: [BacktestRun]
    /// Every run: exported first, then the built-in sample.
    public var runs: [BacktestRun] { directoryRuns + sampleRuns }
    /// The run menu's sections (导出的回测, 内置样例); empty sections left out.
    public var runSections: [BacktestRunSection] {
        [BacktestRunSection(title: "导出的回测", runs: directoryRuns), BacktestRunSection(title: "内置样例", runs: sampleRuns)]
            .filter { !$0.runs.isEmpty }
    }

    public var runID: String
    public var compareID: String?
    /// The shown symbol. Switching it moves to a timeframe it has bars for and, when none of its trades is in
    /// view, to its latest trade.
    public var symbol: String {
        didSet { if symbol != oldValue && !adjusting { symbolChanged() } }
    }
    public var timeframe: BacktestTimeframe = .h4
    public var showsSignals = true
    /// Visible window of the price chart, UTC milliseconds.
    public var window: ClosedRange<Double>
    public var selectedTradeID: String?
    public var loadError: String?

    // Trade list filters
    public var listSymbol: String?
    public var listSide: BacktestSide?
    public var listReason: String?
    public var quickFilter: BacktestQuickFilter = .all

    public static let defaultBars = 220.0

    /// Bumped when a bar or signal file finishes reading, so the charts redraw.
    private var barsRevision = 0
    private var signalsRevision = 0
    @ObservationIgnored private var requestedBars: Set<String> = []
    @ObservationIgnored private var requestedSignals: Set<String> = []
    @ObservationIgnored private var adjusting = false
    /// Folders whose security-scoped access is open, kept open while any of their runs is loaded.
    @ObservationIgnored private var scopedFolders: [URL] = []

    /// - Parameter loadsSavedRuns: also reopen the last folder opened with 打开回测目录… (and, in the iOS
    ///   simulator, ~/Desktop/PortSightBacktests on the Mac running it).
    public init(loadsSavedRuns: Bool = true) {
        let samples = BacktestSample.runs()
        sampleRuns = samples
        let first = samples[0]
        runID = first.id
        symbol = first.symbols.first ?? ""
        let end = first.equity.last?.t ?? first.meta.end
        window = (end - Self.defaultBars * BacktestTimeframe.h4.seconds * 1_000)...end
        if loadsSavedRuns { reopenSavedFolder() }
    }

    public var run: BacktestRun { runs.first { $0.id == runID } ?? sampleRuns[0] }
    public var compareRun: BacktestRun? { compareID.flatMap { id in runs.first { $0.id == id && $0.id != runID } } }
    public var selectedTrade: BacktestTrade? { selectedTradeID.flatMap { id in run.trades.first { $0.id == id } } }

    /// Bars of the shown symbol and timeframe; empty while an exported file is still being read (it is read off
    /// the main thread, and the charts redraw when it arrives).
    public var bars: [BacktestBar] {
        _ = barsRevision
        if let cached = run.cachedBars(symbol, timeframe) { return cached }
        requestBars(run, symbol, timeframe)
        return []
    }

    /// Whether the shown bars are still being read.
    public var isLoadingBars: Bool {
        _ = barsRevision
        return run.cachedBars(symbol, timeframe) == nil
    }

    private func requestBars(_ run: BacktestRun, _ symbol: String, _ timeframe: BacktestTimeframe) {
        let key = run.id + "/" + symbol + "_" + timeframe.rawValue
        guard !requestedBars.contains(key) else { return }
        requestedBars.insert(key)
        Task { [weak self] in
            _ = await run.loadBars(symbol, timeframe)
            self?.requestedBars.remove(key)
            self?.barsRevision += 1
        }
    }

    public var span: Double { window.upperBound - window.lowerBound }

    /// Bars inside the window (plus one either side), merged so the chart never draws more than `limit`.
    public func visibleBars(limit: Int = 320) -> [BacktestBar] {
        TradeChartMath.visibleBars(bars, window: window, limit: limit)
    }

    /// Width of one drawn candle, in milliseconds (wider after merging).
    public func candleSpan(_ visible: [BacktestBar]) -> Double {
        guard visible.count > 1 else { return timeframe.seconds * 1_000 }
        return visible[1].t - visible[0].t
    }

    /// Trades of the shown symbol in the window that can be drawn: a trade without an entry or exit price
    /// (after a delisting, over a bar gap) has no box, but stays in the trade list.
    public func trades(in run: BacktestRun) -> [BacktestTrade] {
        run.trades.filter {
            $0.symbol == symbol && $0.hasPrices && $0.exitT >= window.lowerBound && $0.entryT <= window.upperBound
        }
    }

    public func visibleSignals(limit: Int = 300) -> [BacktestSignalPoint] {
        _ = signalsRevision
        let run = run, symbol = symbol
        guard let all = run.cachedSignals(symbol) else {
            let key = run.id + "/" + symbol
            if !requestedSignals.contains(key) {
                requestedSignals.insert(key)
                Task { [weak self] in
                    _ = await run.loadSignals(symbol)
                    self?.requestedSignals.remove(key)
                    self?.signalsRevision += 1
                }
            }
            return []
        }
        guard !all.isEmpty else { return [] }
        // Binary search for the window's edges (signals are sorted by time).
        func firstIndex(atOrAfter t: Double) -> Int {
            var low = 0, high = all.count
            while low < high { let mid = (low + high) / 2; if all[mid].t < t { low = mid + 1 } else { high = mid } }
            return low
        }
        let start = firstIndex(atOrAfter: window.lowerBound), end = firstIndex(atOrAfter: window.upperBound.nextUp)
        guard start < end else { return [] }
        let count = end - start
        guard count > limit else { return Array(all[start..<end]) }
        let stride = Int((Double(count) / Double(limit)).rounded(.up))
        return Swift.stride(from: start, to: end, by: stride).map { all[$0] }
    }

    /// Price axis for the visible bars, widened to the selected trade's prices, stops and targets, with room
    /// below for the selected trade's size blocks.
    public func priceDomain(_ bars: [BacktestBar]) -> ClosedRange<Double> {
        guard let trade = selectedTrade, trade.symbol == symbol, trade.hasPrices else {
            return TradeChartMath.priceDomain(bars, including: [])
        }
        let levels = [trade.entryPx, trade.exitPx] + trade.stops.map(\.px) + trade.targets.map(\.px)
        return TradeChartMath.priceDomain(bars, including: levels.filter(\.isFinite))
    }

    /// The narrowest trade box under a point.
    public func trade(at t: Double, price: Double, in trades: [BacktestTrade]) -> BacktestTrade? {
        trades.filter { $0.boxContains(t: t, price: price) }
            .min { ($0.exitT - $0.entryT) < ($1.exitT - $1.entryT) }
    }

    // MARK: Timeframes

    /// The timeframe a run opens on for a symbol: the shortest one from 1 hour up whose bars keep a typical
    /// trade of the run within about a third of the default window (so 1 小时 for 12-hour trades, 4 小时 for
    /// week-long ones), falling back to whatever the symbol has. 15 分 is never the default: its files are the
    /// biggest (~10 MB per symbol), and it is one click away.
    public func preferredTimeframe(for run: BacktestRun, symbol: String) -> BacktestTimeframe {
        let available = run.timeframes(symbol)
        guard !available.isEmpty else { return timeframe }
        let hold = max(run.medianHoldHours, 1) * 3_600
        let candidates = available.filter { $0.seconds >= BacktestTimeframe.h1.seconds }
        if let fits = candidates.first(where: { hold / $0.seconds <= Self.defaultBars / 3 }) { return fits }
        return candidates.last ?? available.last ?? timeframe
    }

    // MARK: Moving the window

    private var dataBounds: ClosedRange<Double> {
        let all = run.cachedBars(symbol, timeframe) ?? []
        if let first = all.first?.t, let last = all.last?.t { return first...(last + timeframe.seconds * 1_000) }
        // Bars not read yet (or none): the run's span, widened to the symbol's trades.
        let trades = run.trades(for: symbol)
        var low = run.meta.start > 0 ? run.meta.start : (trades.first?.entryT ?? 0)
        var high = run.meta.end > low ? run.meta.end : (trades.map(\.exitT).max() ?? low + 86_400_000)
        if let first = trades.first?.entryT { low = min(low, first) }
        if let last = trades.map(\.exitT).max() { high = max(high, last) }
        return low...max(high, low + 86_400_000)
    }

    public func setWindow(center: Double, width: Double) {
        let bounds = dataBounds
        let minWidth = 30 * timeframe.seconds * 1_000
        let width = min(max(width, minWidth), bounds.upperBound - bounds.lowerBound)
        var low = center - width / 2
        low = min(max(low, bounds.lowerBound), bounds.upperBound - width)
        window = low...(low + width)
    }

    public func pan(by milliseconds: Double) {
        setWindow(center: (window.lowerBound + window.upperBound) / 2 + milliseconds, width: span)
    }

    /// Zoom around a point (scale < 1 zooms in).
    public func zoom(by scale: Double, around anchor: Double? = nil) {
        let anchor = anchor ?? (window.lowerBound + window.upperBound) / 2
        let width = span * scale
        let fraction = (anchor - window.lowerBound) / max(span, 1)
        let low = anchor - fraction * width
        setWindow(center: low + width / 2, width: width)
    }

    public func showAll() {
        let bounds = dataBounds
        setWindow(center: (bounds.lowerBound + bounds.upperBound) / 2, width: bounds.upperBound - bounds.lowerBound)
    }

    public func jump(to date: Double) { setWindow(center: date, width: span) }

    /// Shows a trade with some room either side and selects it.
    public func focus(_ trade: BacktestTrade) {
        if trade.symbol != symbol {
            adjusting = true
            symbol = trade.symbol
            adjusting = false
            // The new symbol may not have bars at the current timeframe (as in changeRun).
            let available = run.timeframes(symbol)
            if !available.contains(timeframe) { timeframe = preferredTimeframe(for: run, symbol: symbol) }
        }
        selectedTradeID = trade.id
        let length = max(trade.exitT - trade.entryT, timeframe.seconds * 1_000)
        let width = max(length * 3, 80 * timeframe.seconds * 1_000)
        setWindow(center: (trade.entryT + trade.exitT) / 2, width: width)
    }

    public func changeTimeframe(_ new: BacktestTimeframe) {
        let center = (window.lowerBound + window.upperBound) / 2
        let bars = span / (timeframe.seconds * 1_000)
        timeframe = new
        setWindow(center: center, width: min(bars, Self.defaultBars) * new.seconds * 1_000)
    }

    /// Selects a run. Exported runs read trades.json and equity.json here, the first time.
    public func changeRun(_ id: String) {
        let center = (window.lowerBound + window.upperBound) / 2
        runID = id
        if compareID == id { compareID = nil }
        selectedTradeID = nil
        let run = run
        _ = run.trades
        loadError = run.loadError
        if run.skippedTrades > 0, loadError == nil { loadError = "trades.json 里有 \(run.skippedTrades) 笔交易读不出来，已跳过" }
        if listSymbol.map({ !run.symbols.contains($0) }) ?? false { listSymbol = nil }
        if listReason.map({ !exitReasons.contains($0) }) ?? false { listReason = nil }

        adjusting = true
        if !run.symbols.contains(symbol) { symbol = run.symbols.first ?? "" }
        adjusting = false
        timeframe = preferredTimeframe(for: run, symbol: symbol)

        // Keep the same place in time when this run covers it (comparing runs); else show its latest trade.
        let trades = run.trades(for: symbol)
        let width = Self.defaultBars * timeframe.seconds * 1_000
        if let first = trades.first?.entryT, let last = trades.last?.exitT, center >= first, center <= last {
            setWindow(center: center, width: width)
        } else if let latest = trades.last {
            setWindow(center: (latest.entryT + latest.exitT) / 2, width: width)
        } else {
            setWindow(center: run.meta.end, width: width)
        }
    }

    private func symbolChanged() {
        let available = run.timeframes(symbol)
        if !available.isEmpty && !available.contains(timeframe) {
            timeframe = preferredTimeframe(for: run, symbol: symbol)
        }
        let trades = run.trades(for: symbol)
        let inView = trades.contains { $0.exitT >= window.lowerBound && $0.entryT <= window.upperBound }
        if !inView, let latest = trades.last {
            setWindow(center: (latest.entryT + latest.exitT) / 2, width: Self.defaultBars * timeframe.seconds * 1_000)
        } else {
            setWindow(center: (window.lowerBound + window.upperBound) / 2, width: span)
        }
    }

    // MARK: Chart

    public var chartTrades: [BacktestTrade] { trades(in: run) }
    public var comparedTrades: [BacktestTrade] { compareRun.map { trades(in: $0) } ?? [] }

    // MARK: Trade list

    public var listedTrades: [BacktestTrade] {
        var trades = run.trades
        if let listSymbol { trades = trades.filter { $0.symbol == listSymbol } }
        if let listSide { trades = trades.filter { $0.side == listSide } }
        if let listReason { trades = trades.filter { $0.exitReason == listReason } }
        return quickFilter.apply(trades)
    }

    public var exitReasons: [String] { Array(Set(run.trades.map(\.exitReason))).sorted() }

    /// Trade count per symbol, for symbol menus.
    public var tradeCounts: [String: Int] { run.tradeCounts }

    // MARK: Opening an exported directory

    /// Opens one exported run folder, or a folder of runs (index.json, or subfolders with meta.json): every run
    /// goes into the run menu, ahead of the built-in sample, and the first one is shown. Only meta.json is read
    /// now; a run's trades when it is selected, its bars when drawn. Access to the folder stays open while its
    /// runs are loaded, and the folder is reopened on the next launch.
    /// - Parameter remembers: reopen this folder on the next launch.
    public func open(directory: URL, remembers: Bool = true) {
        let scoped = directory.startAccessingSecurityScopedResource()
        do {
            let (loaded, failures) = try BacktestLoader.loadAll(from: directory)
            install(loaded, scope: scoped ? directory : nil)
            if remembers { Self.saveBookmark(for: directory) }
            changeRun(loaded[0].id)
            if !failures.isEmpty {
                loadError = "有 \(failures.count) 个回测读不出来：" + failures.joined(separator: "；")
            }
        } catch {
            if scoped { directory.stopAccessingSecurityScopedResource() }
            loadError = error.localizedDescription
        }
    }

    /// Adds runs (replacing ones with the same id) and closes access to folders no run is read from any more.
    private func install(_ loaded: [BacktestRun], scope: URL?) {
        let ids = Set(loaded.map(\.id))
        directoryRuns.removeAll { ids.contains($0.id) }
        directoryRuns.append(contentsOf: loaded)
        if let scope { scopedFolders.append(scope) }
        let folders = directoryRuns.compactMap { $0.directory?.standardizedFileURL.path() }
        scopedFolders.removeAll { folder in
            let path = folder.standardizedFileURL.path()
            let used = folders.contains { $0.hasPrefix(path) }
            if !used { folder.stopAccessingSecurityScopedResource() }
            return !used
        }
        if compareID.map({ id in !runs.contains { $0.id == id } }) ?? false { compareID = nil }
    }

    private static let bookmarkKey = "PortSight.backtest.lastFolder"

    private static func saveBookmark(for directory: URL) {
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        guard let data = try? directory.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    /// The last folder opened, or a folder of runs in a known place, loaded quietly (nothing shown on failure).
    private func reopenSavedFolder() {
        if let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) {
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
            #else
            let options: URL.BookmarkResolutionOptions = [.withoutUI]
            #endif
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale),
               openQuietly(url) {
                if stale { Self.saveBookmark(for: url) }
                return
            }
        }
        for url in Self.knownFolders() where openQuietly(url) { return }
    }

    private func openQuietly(_ directory: URL) -> Bool {
        let scoped = directory.startAccessingSecurityScopedResource()
        guard let (loaded, _) = try? BacktestLoader.loadAll(from: directory), !loaded.isEmpty else {
            if scoped { directory.stopAccessingSecurityScopedResource() }
            return false
        }
        install(loaded, scope: scoped ? directory : nil)
        changeRun(loaded[0].id)
        loadError = nil
        return true
    }

    /// PORTSIGHT_BACKTESTS, ~/Desktop/PortSightBacktests of the Mac running the iOS simulator, and the app's
    /// own Documents/PortSightBacktests (filled through the Files app).
    private static func knownFolders() -> [URL] {
        var folders: [URL] = []
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["PORTSIGHT_BACKTESTS"], !path.isEmpty { folders.append(URL(filePath: path, directoryHint: .isDirectory)) }
        #if targetEnvironment(simulator)
        if let home = environment["SIMULATOR_HOST_HOME"] {
            folders.append(URL(filePath: home, directoryHint: .isDirectory).appending(path: "Desktop/PortSightBacktests", directoryHint: .isDirectory))
        }
        #endif
        #if os(iOS)
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            folders.append(documents.appending(path: "PortSightBacktests", directoryHint: .isDirectory))
        }
        #endif
        return folders
    }

    // MARK: Helpers

    /// Index of the last bar starting at or before `t` (0 when `t` is before the first bar).
    public static func index(in bars: [BacktestBar], atOrBefore t: Double) -> Int {
        var low = 0, high = bars.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if bars[mid].t <= t { low = mid } else { high = mid - 1 }
        }
        return low
    }
}

/// One section of the run menu.
public struct BacktestRunSection: Identifiable {
    public let title: String
    public let runs: [BacktestRun]
    public var id: String { title }
}

// MARK: - A trade's box on the chart

public extension BacktestTrade {
    /// The price edges of a trade's box, like TradingView's long / short position tool: the entry price splits a
    /// profit part (up to the first target; with no target, up to a winning exit) from a loss part (down to the
    /// first stop; with no stop, down to a losing exit). Either part can be missing.
    static func boxLevels(_ trade: BacktestTrade) -> (profit: Double?, loss: Double?) {
        let target = trade.targets.min { $0.t < $1.t }?.px
        let stop = trade.stops.min { $0.t < $1.t }?.px
        let movedFor = trade.side.sign * (trade.exitPx - trade.entryPx)
        return (target ?? (movedFor > 0 ? trade.exitPx : nil),
                stop ?? (movedFor < 0 ? trade.exitPx : nil))
    }

    /// Whether a point (time, price) falls on this trade's box, with some slack for a finger or pointer.
    func boxContains(t: Double, price: Double) -> Bool {
        guard hasPrices, t >= entryT, t <= exitT else { return false }
        let box = Self.boxLevels(self)
        let levels = [entryPx, exitPx, box.profit, box.loss].compactMap { $0 }
        let low = levels.min() ?? entryPx, high = levels.max() ?? entryPx
        let slack = (high - low) * 0.15 + entryPx * 0.002
        return price >= low - slack && price <= high + slack
    }

    /// Stair-step segments for stops or targets, ending at the exit. Targets end at the half take-profit when
    /// there is one: after it no further target applies (E rule H), though the export keeps the entry point.
    func steps(_ levels: [BacktestLevel]) -> [(from: Double, to: Double, px: Double)] {
        let sorted = levels.sorted { $0.t < $1.t }
        let end = levels == targets ? min(halfTakeProfitT ?? exitT, exitT) : exitT
        return sorted.enumerated().compactMap { index, level in
            let from = max(level.t, entryT)
            let to = index + 1 < sorted.count ? min(sorted[index + 1].t, end) : end
            return to > from ? (from, to, level.px) : nil
        }
    }

    /// Corner points of a stair-step path, for a line.
    static func stairPoints(_ steps: [(from: Double, to: Double, px: Double)]) -> [(t: Double, px: Double)] {
        steps.flatMap { [($0.from, $0.px), ($0.to, $0.px)] }
    }

    /// Position size over time: each size held from its step to the next (or the exit).
    var sizeSteps: [(from: Double, to: Double, w: Double)] {
        let path = sizePath.sorted { $0.t < $1.t }
        return path.enumerated().compactMap { index, step in
            let to = index + 1 < path.count ? path[index + 1].t : exitT
            return to > step.t ? (step.t, to, step.w) : nil
        }
    }
}
