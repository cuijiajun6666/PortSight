//
//  IBKREquity.swift
//  PortSightKit
//
//  The personal IBKR account's value over time (GET /ibkr/equity?range=1d|1w|1m|ytd|1y|all, read only, ETag / 304):
//  net liquidation (nav), the range's cumulative P&L (pnl_cum: change in value minus net deposits) and time-weighted
//  return (twr_cum, a fraction; deposits and withdrawals removed), both from 0 at the range's start, like IBKR's own
//  chart; the deposits and withdrawals in the range (flows, to mark on the curve) and notes on how the figures are
//  worked out (warnings, shown under the chart). 1d is one point a minute over 24 h, 1w one every 15 minutes over
//  7 days (both fall back to daily points while intraday data is still short); the others are daily, the first point
//  being the last report day before the range (the baseline). The last point is the live value when realtime sync is
//  up (source "realtime"), else the last report (source "flex").
//

import Foundation
import Observation

// MARK: - Model

public nonisolated enum IBKREquityRange: String, CaseIterable, Identifiable, Codable, Sendable {
    case day = "1d", week = "1w", month = "1m", ytd = "ytd", year = "1y", all = "all"

    public var id: String { rawValue }

    /// 1天 / 1周 / 1月 / 今年 / 1年 / 全部 (the picker under the chart).
    public var title: String {
        switch self {
        case .day: "1天"
        case .week: "1周"
        case .month: "1月"
        case .ytd: "今年"
        case .year: "1年"
        case .all: "全部"
        }
    }

    /// Points within a day (minute / 15-minute samples) rather than one per report day.
    public var isIntraday: Bool { self == .day || self == .week }

    /// The default when nothing was chosen (the relay's default too).
    public static let standard: IBKREquityRange = .month
}

public nonisolated struct IBKREquityPoint: Codable, Equatable, Sendable, Identifiable {
    /// UTC; a report day is YYYY-MM-DDT00:00:00Z, an intraday point the moment it was sampled.
    public var t: String
    public var nav: Double?
    public var pnl_cum: Double?
    public var twr_cum: Double?

    public var id: String { t }
    public var date: Date? { JournalTime.milliseconds(t).map { Date(timeIntervalSince1970: $0 / 1_000) } }

    private enum CodingKeys: String, CodingKey { case t, nav, pnl_cum, twr_cum }

    public init(t: String, nav: Double?, pnl_cum: Double? = nil, twr_cum: Double? = nil) {
        self.t = t
        self.nav = nav
        self.pnl_cum = pnl_cum
        self.twr_cum = twr_cum
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let t = c.lenientString(.t), !t.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .t, in: c, debugDescription: "point without time")
        }
        self.t = t
        nav = c.lenientDouble(.nav)
        pnl_cum = c.lenientDouble(.pnl_cum)
        twr_cum = c.lenientDouble(.twr_cum)
    }
}

public nonisolated struct IBKREquityFlow: Codable, Equatable, Sendable, Identifiable {
    public var t: String
    /// In the base currency: in positive, out negative.
    public var amount: Double
    /// deposit / withdrawal / transfer_in / transfer_out.
    public var type: String?

    public var id: String { t + "|" + (type ?? "") + "|" + String(amount) }
    public var date: Date? { JournalTime.milliseconds(t).map { Date(timeIntervalSince1970: $0 / 1_000) } }
    public var isIn: Bool { amount >= 0 }

    /// 入金 / 出金 / 转入 / 转出.
    public var title: String {
        switch type?.lowercased() {
        case "deposit": "入金"
        case "withdrawal": "出金"
        case "transfer_in": "转入"
        case "transfer_out": "转出"
        default: isIn ? "入金" : "出金"
        }
    }

    private enum CodingKeys: String, CodingKey { case t, amount, type }

    public init(t: String, amount: Double, type: String?) {
        self.t = t
        self.amount = amount
        self.type = type
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let t = c.lenientString(.t), let amount = c.lenientDouble(.amount) else {
            throw DecodingError.dataCorruptedError(forKey: .t, in: c, debugDescription: "flow without time or amount")
        }
        self.t = t
        self.amount = amount
        type = c.lenientString(.type)
    }
}

public nonisolated struct IBKREquity: Codable, Equatable, Sendable {
    public var available: Bool?
    public var range: String?
    public var currency: String?
    public var points: [IBKREquityPoint] = []
    public var flows: [IBKREquityFlow] = []
    public var as_of: String?
    public var source: String?
    /// How the figures are worked out (shown under the chart), e.g. that returns may be off until Transfers is in
    /// the Flex query.
    public var warnings: [String] = []

    private enum CodingKeys: String, CodingKey { case available, range, currency, points, flows, as_of, source, warnings }

    public init(available: Bool? = true, range: String? = nil, currency: String? = "USD", points: [IBKREquityPoint] = [],
                flows: [IBKREquityFlow] = [], as_of: String? = nil, source: String? = "realtime", warnings: [String] = []) {
        self.available = available
        self.range = range
        self.currency = currency
        self.points = points
        self.flows = flows
        self.as_of = as_of
        self.source = source
        self.warnings = warnings
    }

    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        available = c.lenientBool(.available)
        range = c.lenientString(.range)
        currency = c.lenientString(.currency)
        points = ((try? c.decodeIfPresent([Lossy<IBKREquityPoint>].self, forKey: .points)) ?? []).compactMap(\.value)
            .filter { $0.date != nil }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        flows = ((try? c.decodeIfPresent([Lossy<IBKREquityFlow>].self, forKey: .flows)) ?? []).compactMap(\.value)
            .filter { $0.date != nil }
        as_of = c.lenientString(.as_of)
        source = c.lenientString(.source)
        warnings = ((try? c.decodeIfPresent([JournalText].self, forKey: .warnings)) ?? []).compactMap(\.value)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Points with a value, oldest first.
    public var valued: [IBKREquityPoint] { points.filter { $0.nav != nil } }

    /// The range's cumulative P&L and time-weighted return (the last point's), nil without points.
    public var pnl: Double? { points.last(where: { $0.pnl_cum != nil })?.pnl_cum }
    public var twr: Double? { points.last(where: { $0.twr_cum != nil })?.twr_cum }
    /// The latest value.
    public var lastValue: Double? { valued.last?.nav }

    public var isRealtime: Bool { source?.lowercased() == "realtime" }

    /// As the chart points the pages already draw (equity = nav; drawdown from the running peak; no benchmark,
    /// so the benchmark is the value itself).
    public var chartPoints: [DemoPoint] {
        var peak = 0.0
        return valued.enumerated().compactMap { index, point in
            guard let nav = point.nav, let date = point.date else { return nil }
            peak = max(peak, nav)
            return DemoPoint(id: index, date: date, equity: nav, benchmark: nav, drawdown: peak > 0 ? (peak - nav) / peak : 0)
        }
    }

    /// The largest fall from a high within the range, as a fraction.
    public var maxDrawdown: Double { chartPoints.map(\.drawdown).max() ?? 0 }
}

/// What a conditional GET found.
public nonisolated enum RelayConditionalRead: Sendable {
    /// 304: nothing new since the ETag sent.
    case notModified
    case changed(Data, etag: String?)
}

// MARK: - Store

/// One document per range, each kept on disk with its ETag so a read that finds nothing new costs a 304. Read
/// through the paired relay (ServerStore.readConditional); dropped when the relay is unpaired or replaced.
@Observable
public final class IBKREquityStore {
    public static let shared = IBKREquityStore()

    public typealias Phase = RelayFeedStore<IBKREquity>.Phase
    public typealias Reader = (RelayEndpoint, [URLQueryItem], String?) async throws -> RelayConditionalRead

    public private(set) var documents: [IBKREquityRange: IBKREquity] = [:]
    public private(set) var phases: [IBKREquityRange: Phase] = [:]
    /// When each range was last confirmed current (a 200 or a 304).
    public private(set) var readAt: [IBKREquityRange: Date] = [:]
    /// Ranges whose document is a saved copy (the last read failed, or it came from disk).
    public private(set) var saved: Set<IBKREquityRange> = []

    /// The page on screen reads its range this often (a 304 when nothing changed).
    public static let interval: TimeInterval = 10

    @ObservationIgnored private var etags: [IBKREquityRange: String] = [:]
    @ObservationIgnored private var lastAttempt: [IBKREquityRange: Date] = [:]
    @ObservationIgnored private var inFlight: [IBKREquityRange: Task<Void, Never>] = [:]
    @ObservationIgnored private var loadedFrom: String?
    @ObservationIgnored private let read: Reader
    @ObservationIgnored private let currentBase: () -> String?
    @ObservationIgnored private let cacheName: String?
    /// Shortest gap between automatic reads of one range (Self.interval; tests use a longer one).
    @ObservationIgnored private let minGap: TimeInterval

    public init(read: Reader? = nil, base: (() -> String?)? = nil, cacheName: String? = "ibkr_equity.json",
                minGap: TimeInterval = IBKREquityStore.interval) {
        self.minGap = minGap
        self.read = read ?? { endpoint, query, etag in
            try await ServerStore.shared.readConditional(endpoint, query: query, etag: etag)
        }
        self.currentBase = base ?? {
            let server = ServerStore.shared
            return server.isPaired && RelayNotices.usesRelay ? server.baseURL : nil
        }
        self.cacheName = cacheName
        restore()
    }

    public func document(_ range: IBKREquityRange) -> IBKREquity? { documents[range] }
    public func phase(_ range: IBKREquityRange) -> Phase { phases[range] ?? (documents[range] == nil ? .idle : .loaded) }
    public func isSaved(_ range: IBKREquityRange) -> Bool { saved.contains(range) }

    /// Reads `range` unless it was read under 10 s ago (`force` reads now). Callers arriving while that range is
    /// being read wait for it.
    public func load(_ range: IBKREquityRange, force: Bool = false) async {
        guard let base = currentBase() else {
            if loadedFrom != nil || !documents.isEmpty { reset() }
            return
        }
        if let running = inFlight[range] {
            await running.value
            return
        }
        if loadedFrom != nil, loadedFrom != base { reset() }
        if !force, let last = lastAttempt[range], Date.now.timeIntervalSince(last) < minGap - 0.5 { return }
        lastAttempt[range] = .now
        let task = Task { await self.perform(range, base: base) }
        inFlight[range] = task
        await task.value
        inFlight[range] = nil
    }

    /// While a chart is on screen (and the app in front): its range now, then every 10 s until cancelled.
    public func runPolling(_ range: IBKREquityRange) async {
        while !Task.isCancelled {
            await load(range)
            try? await Task.sleep(for: .seconds(Self.interval))
        }
    }

    /// Forgets every range (unpaired, or another relay) and the saved copy.
    public func reset() {
        for task in inFlight.values { task.cancel() }
        inFlight = [:]
        documents = [:]
        phases = [:]
        readAt = [:]
        saved = []
        etags = [:]
        lastAttempt = [:]
        loadedFrom = nil
        if let url = cacheURL { try? FileManager.default.removeItem(at: url) }
    }

    /// For tests and previews.
    public func show(_ document: IBKREquity, for range: IBKREquityRange) {
        documents[range] = document
        phases[range] = .loaded
        readAt[range] = .now
        saved.remove(range)
    }

    private func perform(_ range: IBKREquityRange, base: String) async {
        if documents[range] == nil { phases[range] = .loading }
        let etag = documents[range] == nil ? nil : etags[range]
        do {
            let answer = try await read(.ibkrEquity, [URLQueryItem(name: "range", value: range.rawValue)], etag)
            guard currentBase() == base else { return }
            loadedFrom = base
            switch answer {
            case .notModified:
                phases[range] = .loaded
            case .changed(let data, let newTag):
                let document = try JSONDecoder().decode(IBKREquity.self, from: data)
                if document.available == false {
                    documents[range] = nil
                    etags[range] = nil
                    phases[range] = .unavailable("还没有账户走势数据")
                } else {
                    documents[range] = document
                    etags[range] = newTag
                    phases[range] = .loaded
                }
            }
            readAt[range] = .now
            saved.remove(range)
            save(base: base)
        } catch {
            guard currentBase() == base else { return }
            if RelayAPI.isCancellation(error) {
                if phases[range] == .loading { phases[range] = documents[range] == nil ? .idle : .loaded }
                lastAttempt[range] = nil
                return
            }
            let next: Phase
            switch error {
            case ServerError.http(404): next = .notOpen
            case ServerError.http(400): next = .failed("服务器不支持这个区间")
            case ServerError.unauthorized: next = .needsRepair
            case ServerError.rateLimited: next = .rateLimited
            case ServerError.http(403): next = .failed("服务器暂时拒绝了这项请求（403），稍后自动再试")
            case ServerError.http(let status): next = .failed("服务器返回 \(status)")
            case is DecodingError: next = .failed("服务器返回的内容读不懂")
            case ServerError.notPaired, ServerError.invalidURL: next = .unpaired
            default: next = .failed("连不上服务器（检查网络）")
            }
            if next == .notOpen {
                documents[range] = nil
                etags[range] = nil
            } else if documents[range] != nil {
                saved.insert(range)
            }
            phases[range] = next
        }
    }

    // MARK: Disk

    private struct Saved: Codable {
        struct Entry: Codable {
            var document: IBKREquity
            var etag: String?
            var readAt: Date?
        }
        var base: String
        var entries: [String: Entry]
    }

    private var cacheURL: URL? { cacheName.map { RelayCache.directory.appendingPathComponent($0) } }

    private func save(base: String) {
        guard let url = cacheURL else { return }
        var entries: [String: Saved.Entry] = [:]
        for (range, document) in documents {
            entries[range.rawValue] = Saved.Entry(document: document, etag: etags[range], readAt: readAt[range])
        }
        guard let data = try? JSONEncoder().encode(Saved(base: base, entries: entries)) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func restore() {
        guard let url = cacheURL, let base = currentBase(), let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(Saved.self, from: data), saved.base == base else { return }
        for (key, entry) in saved.entries {
            guard let range = IBKREquityRange(rawValue: key) else { continue }
            documents[range] = entry.document
            etags[range] = entry.etag
            readAt[range] = entry.readAt
            phases[range] = .loaded
            self.saved.insert(range)
        }
        loadedFrom = base
    }
}
