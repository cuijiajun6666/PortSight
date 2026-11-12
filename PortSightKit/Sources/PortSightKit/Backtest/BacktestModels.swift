//
//  BacktestModels.swift
//  PortSight
//
//  One backtest result exported by the quant system (portsight_backtest_viewer_brief.md §三): a directory with
//  meta.json, trades.json, equity.json, bars/<SYMBOL>_<TF>.json and optional signals/<SYMBOL>.json. Times are
//  UTC milliseconds. The app only reads these; it never runs a backtest.
//

import Foundation

public struct BacktestMeta: Codable, Hashable {
    public let runID: String
    public let strategy: String
    public let protocolSHA: String
    public let segment: String
    public let start: Double
    public let end: Double
    public let verdict: String
    public let costModel: String
    public let notes: String?
    /// Symbols and timeframes the exporter says the run covers, and its trade count (empty / nil when not given).
    public let listedSymbols: [String]
    public let listedTimeframes: [String]
    public let tradeCount: Int?

    enum CodingKeys: String, CodingKey {
        case runID = "run_id", strategy, protocolSHA = "protocol_sha", segment, start, end, verdict
        case costModel = "cost_model", notes, listedSymbols = "symbols", listedTimeframes = "timeframes"
        case tradeCount = "n_trades", summary
    }
    private struct Summary: Decodable { let trades: Int? }

    public init(runID: String, strategy: String, protocolSHA: String, segment: String, start: Double, end: Double,
                verdict: String, costModel: String, notes: String?, listedSymbols: [String] = [],
                listedTimeframes: [String] = [], tradeCount: Int? = nil) {
        self.runID = runID; self.strategy = strategy; self.protocolSHA = protocolSHA; self.segment = segment
        self.start = start; self.end = end; self.verdict = verdict; self.costModel = costModel; self.notes = notes
        self.listedSymbols = listedSymbols; self.listedTimeframes = listedTimeframes; self.tradeCount = tradeCount
    }

    /// Only run_id is required; every other field falls back to empty, and unknown keys (checks, sources,
    /// stats_reported …) are ignored.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runID = try c.decode(String.self, forKey: .runID)
        strategy = (try? c.decodeIfPresent(String.self, forKey: .strategy)) ?? runID
        protocolSHA = (try? c.decodeIfPresent(String.self, forKey: .protocolSHA)) ?? ""
        segment = (try? c.decodeIfPresent(String.self, forKey: .segment)) ?? ""
        start = (try? c.decodeIfPresent(Double.self, forKey: .start)) ?? 0
        end = (try? c.decodeIfPresent(Double.self, forKey: .end)) ?? 0
        verdict = (try? c.decodeIfPresent(String.self, forKey: .verdict)) ?? ""
        costModel = (try? c.decodeIfPresent(String.self, forKey: .costModel)) ?? ""
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        listedSymbols = (try? c.decodeIfPresent([String].self, forKey: .listedSymbols)) ?? []
        listedTimeframes = (try? c.decodeIfPresent([String].self, forKey: .listedTimeframes)) ?? []
        // The quant system's own samples put the count under summary.trades instead of n_trades.
        tradeCount = (try? c.decodeIfPresent(Int.self, forKey: .tradeCount))
            ?? (try? c.decodeIfPresent(Summary.self, forKey: .summary))?.trades
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(runID, forKey: .runID); try c.encode(strategy, forKey: .strategy)
        try c.encode(protocolSHA, forKey: .protocolSHA); try c.encode(segment, forKey: .segment)
        try c.encode(start, forKey: .start); try c.encode(end, forKey: .end); try c.encode(verdict, forKey: .verdict)
        try c.encode(costModel, forKey: .costModel); try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(listedSymbols, forKey: .listedSymbols); try c.encode(listedTimeframes, forKey: .listedTimeframes)
        try c.encodeIfPresent(tradeCount, forKey: .tradeCount)
    }

    public var segmentTitle: String {
        switch segment {
        case "discovery": "发现段"
        case "confirmation", "confirm": "确认段"
        default: segment
        }
    }

    /// The strategy's name without its explanation in brackets, for titles and menus (exported strategies are
    /// often a whole sentence).
    public var shortTitle: String {
        var title = strategy
        for mark in [" (", "（", ": ", "；"] {
            if let range = title.range(of: mark), title.distance(from: title.startIndex, to: range.lowerBound) >= 3 {
                title = String(title[..<range.lowerBound])
            }
        }
        if title.count > 48 { title = String(title.prefix(47)) + "…" }
        return title.isEmpty ? runID : title
    }

    /// A line for the run menus: the run id, and the short strategy name when it says more.
    public var menuTitle: String {
        shortTitle == runID ? runID : runID + " · " + shortTitle
    }

    /// 过 / 不过 / 只报告, read from the free-form verdict.
    public var verdictKind: BacktestVerdict {
        let text = verdict.lowercased()
        if text.contains("fail") || text.contains("reject") || verdict.contains("不过") { return .fail }
        if text.contains("report") || verdict.contains("只报告") { return .reportOnly }
        if text.contains("pass") || text.contains("select") || verdict.contains("过") { return .pass }
        return .reportOnly
    }
}

public enum BacktestVerdict: String {
    case pass = "过", fail = "不过", reportOnly = "只报告"
}

/// Plain values, decoded off the main thread (bar files run to ~10 MB per symbol at 15 minutes).
nonisolated public struct BacktestBar: Codable, Hashable, Sendable {
    public let t: Double
    public let o: Double
    public let h: Double
    public let l: Double
    public let c: Double
    public let v: Double

    public init(t: Double, o: Double, h: Double, l: Double, c: Double, v: Double) {
        self.t = t; self.o = o; self.h = h; self.l = l; self.c = c; self.v = v
    }

    public var date: Date { Date(milliseconds: t) }
}

nonisolated public enum BacktestTimeframe: String, CaseIterable, Identifiable, Codable {
    case m1 = "1m", m5 = "5m", m15 = "15m", h1 = "1h", h4 = "4h", d1 = "1d"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .m1: "1 分钟"
        case .m5: "5 分钟"
        case .m15: "15 分钟"
        case .h1: "1 小时"
        case .h4: "4 小时"
        case .d1: "日"
        }
    }
    /// Compact label for segmented pickers (1分 / 5分 / 15分 / 1小时 …).
    public var shortTitle: String {
        switch self {
        case .m1: "1分"
        case .m5: "5分"
        case .m15: "15分"
        case .h1: "1小时"
        case .h4: "4小时"
        case .d1: "日"
        }
    }
    public var seconds: Double {
        switch self {
        case .m1: 60
        case .m5: 300
        case .m15: 900
        case .h1: 3_600
        case .h4: 14_400
        case .d1: 86_400
        }
    }
}

nonisolated public enum BacktestSide: String, Codable {
    case long, short
    public var sign: Double { self == .long ? 1 : -1 }
    public var title: String { self == .long ? "多" : "空" }
}

nonisolated public struct BacktestSizeStep: Codable, Hashable {
    /// Time in UTC milliseconds.
    public let t: Double
    /// Share of net asset value; negative for shorts.
    public let w: Double
    /// open / add / reduce / partial_tp / close …
    public let why: String

    public init(t: Double, w: Double, why: String) { self.t = t; self.w = w; self.why = why }

    enum CodingKeys: String, CodingKey { case t, w, why }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decode(Double.self, forKey: .t)
        w = (try? c.decodeIfPresent(Double.self, forKey: .w)) ?? 0
        why = (try? c.decodeIfPresent(String.self, forKey: .why)) ?? ""
    }

    public var title: String {
        switch why {
        case "open": "开仓"
        case "add": "加仓"
        case "reduce": "减仓"
        case "partial_tp", "partial_take_profit": "部分止盈"
        case "half_tp", "half_take_profit", "half_off": "半仓止盈"
        case "close": "平仓"
        case "liquidated", "liquidation": "强平"
        default: why
        }
    }
}

nonisolated public struct BacktestLevel: Codable, Hashable {
    public let t: Double
    public let px: Double
    public init(t: Double, px: Double) { self.t = t; self.px = px }
}

/// The hedge leg some exports attach to a trade (F listing: a BTC perp against each short).
nonisolated public struct BacktestHedge: Codable, Hashable {
    public let symbol: String
    public let side: BacktestSide?
    public let w: Double?
    public let entryPx: Double?
    public let exitPx: Double?

    enum CodingKeys: String, CodingKey { case symbol, side, w, entryPx = "entry_px", exitPx = "exit_px" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = (try? c.decodeIfPresent(String.self, forKey: .symbol)) ?? ""
        side = try? c.decodeIfPresent(BacktestSide.self, forKey: .side)
        w = try? c.decodeIfPresent(Double.self, forKey: .w)
        entryPx = try? c.decodeIfPresent(Double.self, forKey: .entryPx)
        exitPx = try? c.decodeIfPresent(Double.self, forKey: .exitPx)
    }
}

/// One exported trade. Real exports leave fields out or null (entry_px / exit_px after a delisting or over a bar
/// gap; pnl_gross, fee, funding, mfe, mae or signals_at_entry for whole runs) and add keys of their own (hedge,
/// extensions, entered_in_lockbox …). Missing values are kept as nil in the `reported…` / `…Price` fields; the
/// plain accessors (`entryPx`, `pnlGross` …) give NaN for a missing price and 0 for a missing P&L part, so code
/// that only draws or sums keeps working. Use `hasPrices` before drawing a trade's box and the `…Text` helpers
/// for a "—".
nonisolated public struct BacktestTrade: Codable, Hashable, Identifiable {
    public let id: String
    public let symbol: String
    public let side: BacktestSide
    public let entryT: Double
    public let entryPrice: Double?
    public let exitT: Double
    public let exitPrice: Double?
    public let exitReason: String
    public let sizePath: [BacktestSizeStep]
    public let stops: [BacktestLevel]
    public let targets: [BacktestLevel]
    public let reportedPnlGross: Double?
    public let reportedFee: Double?
    public let reportedFunding: Double?
    public let pnlNet: Double
    public let reportedMfe: Double?
    public let reportedMae: Double?
    public let holdH: Double
    public let signalsAtEntry: [String: Double]
    public let hedge: BacktestHedge?
    /// How many times the hold was extended (E rule H), when exported.
    public let extensions: Int?
    /// false for a lockbox trade opened before the exam window: its pnl_net covers only the part inside it.
    public let enteredInLockbox: Bool?

    enum CodingKeys: String, CodingKey {
        case id, symbol, side, entryT = "entry_t", entryPrice = "entry_px", exitT = "exit_t", exitPrice = "exit_px"
        case exitReason = "exit_reason", sizePath = "size_path", stops, targets, reportedPnlGross = "pnl_gross"
        case reportedFee = "fee", reportedFunding = "funding", pnlNet = "pnl_net", reportedMfe = "mfe"
        case reportedMae = "mae", holdH = "hold_h", signalsAtEntry = "signals_at_entry", hedge, extensions
        case enteredInLockbox = "entered_in_lockbox"
    }

    /// A non-finite price (NaN) means "not known".
    public init(id: String, symbol: String, side: BacktestSide, entryT: Double, entryPx: Double, exitT: Double,
                exitPx: Double, exitReason: String, sizePath: [BacktestSizeStep], stops: [BacktestLevel],
                targets: [BacktestLevel], pnlGross: Double?, fee: Double?, funding: Double?, pnlNet: Double,
                mfe: Double?, mae: Double?, holdH: Double, signalsAtEntry: [String: Double],
                hedge: BacktestHedge? = nil, extensions: Int? = nil, enteredInLockbox: Bool? = nil) {
        self.id = id; self.symbol = symbol; self.side = side; self.entryT = entryT
        self.entryPrice = entryPx.isFinite ? entryPx : nil
        self.exitT = exitT; self.exitPrice = exitPx.isFinite ? exitPx : nil
        self.exitReason = exitReason; self.sizePath = sizePath
        self.stops = stops; self.targets = targets
        self.reportedPnlGross = pnlGross; self.reportedFee = fee; self.reportedFunding = funding
        self.pnlNet = pnlNet; self.reportedMfe = mfe; self.reportedMae = mae; self.holdH = holdH
        self.signalsAtEntry = signalsAtEntry
        self.hedge = hedge; self.extensions = extensions; self.enteredInLockbox = enteredInLockbox
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        symbol = try c.decode(String.self, forKey: .symbol)
        entryT = try c.decode(Double.self, forKey: .entryT)
        entryPrice = Self.finite(try? c.decodeIfPresent(Double.self, forKey: .entryPrice))
        exitPrice = Self.finite(try? c.decodeIfPresent(Double.self, forKey: .exitPrice))
        let hold = Self.finite(try? c.decodeIfPresent(Double.self, forKey: .holdH))
        let exit = (try? c.decodeIfPresent(Double.self, forKey: .exitT)) ?? entryT + (hold ?? 0) * 3_600_000
        exitT = exit
        holdH = hold ?? max(0, exit - entryT) / 3_600_000
        exitReason = (try? c.decodeIfPresent(String.self, forKey: .exitReason)) ?? ""
        sizePath = (try? c.decodeIfPresent(LossyArray<BacktestSizeStep>.self, forKey: .sizePath))?.items ?? []
        stops = (try? c.decodeIfPresent(LossyArray<BacktestLevel>.self, forKey: .stops))?.items ?? []
        targets = (try? c.decodeIfPresent(LossyArray<BacktestLevel>.self, forKey: .targets))?.items ?? []
        // A side the app does not know: read it from the first size step's sign.
        side = (try? c.decode(BacktestSide.self, forKey: .side)) ?? ((sizePath.first?.w ?? 0) < 0 ? .short : .long)
        reportedPnlGross = Self.finite(try? c.decodeIfPresent(Double.self, forKey: .reportedPnlGross))
        reportedFee = Self.finite(try? c.decodeIfPresent(Double.self, forKey: .reportedFee))
        reportedFunding = Self.finite(try? c.decodeIfPresent(Double.self, forKey: .reportedFunding))
        pnlNet = Self.finite(try? c.decodeIfPresent(Double.self, forKey: .pnlNet)) ?? 0
        reportedMfe = Self.finite(try? c.decodeIfPresent(Double.self, forKey: .reportedMfe))
        reportedMae = Self.finite(try? c.decodeIfPresent(Double.self, forKey: .reportedMae))
        let signals = try? c.decodeIfPresent([String: LossyNumber].self, forKey: .signalsAtEntry)
        signalsAtEntry = (signals ?? [:]).compactMapValues(\.value)
        hedge = try? c.decodeIfPresent(BacktestHedge.self, forKey: .hedge)
        extensions = try? c.decodeIfPresent(Int.self, forKey: .extensions)
        enteredInLockbox = try? c.decodeIfPresent(Bool.self, forKey: .enteredInLockbox)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(symbol, forKey: .symbol); try c.encode(side, forKey: .side)
        try c.encode(entryT, forKey: .entryT); try c.encodeIfPresent(entryPrice, forKey: .entryPrice)
        try c.encode(exitT, forKey: .exitT); try c.encodeIfPresent(exitPrice, forKey: .exitPrice)
        try c.encode(exitReason, forKey: .exitReason); try c.encode(sizePath, forKey: .sizePath)
        try c.encode(stops, forKey: .stops); try c.encode(targets, forKey: .targets)
        try c.encodeIfPresent(reportedPnlGross, forKey: .reportedPnlGross)
        try c.encodeIfPresent(reportedFee, forKey: .reportedFee)
        try c.encodeIfPresent(reportedFunding, forKey: .reportedFunding)
        try c.encode(pnlNet, forKey: .pnlNet)
        try c.encodeIfPresent(reportedMfe, forKey: .reportedMfe); try c.encodeIfPresent(reportedMae, forKey: .reportedMae)
        try c.encode(holdH, forKey: .holdH); try c.encode(signalsAtEntry, forKey: .signalsAtEntry)
        try c.encodeIfPresent(hedge, forKey: .hedge); try c.encodeIfPresent(extensions, forKey: .extensions)
        try c.encodeIfPresent(enteredInLockbox, forKey: .enteredInLockbox)
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    /// Entry and exit price; NaN when the export has none (see `hasPrices`).
    public var entryPx: Double { entryPrice ?? .nan }
    public var exitPx: Double { exitPrice ?? .nan }
    /// Both prices known, so the trade can be drawn as a box.
    public var hasPrices: Bool { entryPrice != nil && exitPrice != nil }

    public var pnlGross: Double { reportedPnlGross ?? 0 }
    public var fee: Double { reportedFee ?? 0 }
    public var funding: Double { reportedFunding ?? 0 }
    public var mfe: Double { reportedMfe ?? 0 }
    public var mae: Double { reportedMae ?? 0 }

    public var entryDate: Date { Date(milliseconds: entryT) }
    public var exitDate: Date { Date(milliseconds: exitT) }
    /// NaN when a price is missing; `knownPriceReturn` is nil then.
    public var priceReturn: Double { side.sign * (exitPx / entryPx - 1) }
    public var knownPriceReturn: Double? { hasPrices ? priceReturn : nil }
    public var exitTitle: String { BacktestExitReason.title(exitReason) }
    public var isWin: Bool { pnlNet > 0 }

    /// "—" for a missing price.
    public var entryPriceText: String { entryPrice.map(BacktestFormat.price) ?? "—" }
    public var exitPriceText: String { exitPrice.map(BacktestFormat.price) ?? "—" }

    /// Largest share of net asset value held during the trade.
    public var peakWeight: Double { sizePath.map { abs($0.w) }.max() ?? 0 }

    /// When a trade with a take-profit target first cut its size: the half take-profit (E rule H). After it no
    /// further target applies, though the export keeps the target point at entry.
    public var halfTakeProfitT: Double? {
        guard !targets.isEmpty else { return nil }
        return sizePath.sorted { $0.t < $1.t }.first {
            $0.t > entryT && ["reduce", "partial_tp", "partial_take_profit", "half_tp", "half_take_profit", "half_off"].contains($0.why)
        }?.t
    }

    /// A size step's name; the cut at a trade's take-profit target reads 半仓止盈 rather than 减仓.
    public func title(of step: BacktestSizeStep) -> String {
        if step.why == "reduce", let t = halfTakeProfitT, step.t == t { return "半仓止盈" }
        return step.title
    }
}

nonisolated public enum BacktestExitReason {
    /// 止盈 / 止损 / 到期 / 信号反转 / 风控截断 / 下架结算 …, and the raw snake_case label for anything unknown.
    public static func title(_ raw: String) -> String {
        switch raw {
        case "take_profit", "target", "tp": "止盈"
        case "half_take_profit", "half_tp", "partial_tp", "partial_take_profit": "半仓止盈"
        case "stop_loss", "stop", "sl", "trailing_stop", "vol_stop": "止损"
        case "time", "expiry", "time_exit", "timeout", "hold_end": "到期"
        case "max_hold", "max_hold_exit": "最长持有"
        case "signal_exit": "信号退出"
        case "signal_reverse", "signal_flip": "信号反转"
        case "rebalance_exit", "rebalance": "调仓退出"
        case "risk_cut", "risk_cap", "risk": "风控截断"
        case "delist", "delisting", "settlement", "delist_settlement", "path_ended": "下架结算"
        case "liquidated", "liquidation": "强平"
        case "data_end", "end_of_data": "数据结束"
        case "open": "持仓中"
        default: raw
        }
    }
}

/// Decodes the elements it can and drops the rest (a level with a null price, say).
nonisolated struct LossyArray<Element: Decodable>: Decodable {
    let items: [Element]
    /// Elements that could not be decoded.
    let skipped: Int

    /// Accepts any value, so the container moves past an element that did not decode.
    private struct Skip: Decodable { init(from decoder: Decoder) throws {} }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var items: [Element] = []
        var skipped = 0
        while !container.isAtEnd {
            if let item = try? container.decode(Element.self) { items.append(item) } else {
                _ = try? container.decode(Skip.self)
                skipped += 1
            }
        }
        self.items = items
        self.skipped = skipped
    }
}

/// A number that may come as null, a boolean or a numeric string.
nonisolated struct LossyNumber: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = nil }
        else if let number = try? c.decode(Double.self) { value = number.isFinite ? number : nil }
        else if let flag = try? c.decode(Bool.self) { value = flag ? 1 : 0 }
        else if let text = try? c.decode(String.self) { value = Double(text) }
        else { value = nil }
    }
}

public struct BacktestEquityPoint: Codable, Hashable {
    public let t: Double
    public let nav: Double
    public let dd: Double
    public let benchNav: Double?

    enum CodingKeys: String, CodingKey { case t, nav, dd, benchNav = "bench_nav" }

    public init(t: Double, nav: Double, dd: Double, benchNav: Double?) {
        self.t = t; self.nav = nav; self.dd = dd; self.benchNav = benchNav
    }

    /// A missing dd is NaN here; BacktestRun recomputes the column from NAV then.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decode(Double.self, forKey: .t)
        nav = try c.decode(Double.self, forKey: .nav)
        dd = (try? c.decodeIfPresent(Double.self, forKey: .dd)) ?? .nan
        benchNav = try? c.decodeIfPresent(Double.self, forKey: .benchNav)
    }

    public var date: Date { Date(milliseconds: t) }
}

/// One row of signals/<SYMBOL>.json: a time and any number of named values (mu_4h, entry_thr, …).
nonisolated public struct BacktestSignalPoint: Decodable, Hashable, Sendable {
    public let t: Double
    public let values: [String: Double]

    public init(t: Double, values: [String: Double]) { self.t = t; self.values = values }

    public init(from decoder: Decoder) throws {
        var all = try decoder.singleValueContainer().decode([String: Double?].self).compactMapValues { $0 }
        guard let t = all.removeValue(forKey: "t") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "signal row without t"))
        }
        self.t = t
        values = all
    }

    public var date: Date { Date(milliseconds: t) }

    /// Threshold series are drawn dashed.
    public static func isThreshold(_ key: String) -> Bool { key.hasSuffix("_thr") || key.contains("threshold") }
}

nonisolated extension Date {
    public init(milliseconds: Double) { self.init(timeIntervalSince1970: milliseconds / 1_000) }
    public var milliseconds: Double { timeIntervalSince1970 * 1_000 }
}
