//
//  TradeJournal.swift
//  PortSightKit
//
//  GET /journal (G395 交易理由卡, card_schema "g395.card.v1"): the v4 shadow writes one card whenever it really
//  trades (open, add, reduce, close, flip …); the relay returns the last 7 days, at most 2000 cards. While the
//  relay's publishing switch is off it answers 404, which means "not open yet", not an error.
//
//  Every field is optional and read leniently (a number may come as a string, a list may hold an odd element), so a
//  newer or older card still shows what it has. Cards are matched to a trade by coin and time (see `cards(symbol:…)`).
//
//  Sealed rule: while a card is sealed it carries no return, P&L or IC, and nothing here works one out from prices.
//  Until 2027-05-06 the app shows no result numbers for these cards.
//

import Foundation

// MARK: - Document

/// The /journal document: as_of, line, kind "journal", sealed, card_schema, window, counts, cards.
public nonisolated struct TradeJournal: Decodable, Equatable, Sendable {
    public var as_of: String?
    public var line: String?
    public var kind: String?
    public var sealed: Bool?
    public var card_schema: String?
    public var window: JournalWindow?
    /// Whatever the relay counts (by kind, coin …); numbers only.
    public var counts: [String: Double] = [:]
    /// Unique by id, newest first.
    public var cards: [JournalCard] = []
    /// The relay cut the list (at `limit`); `covered_from` is where the cards sent really start.
    public var truncated: Bool?
    public var covered_from: String?
    /// Cards the relay holds for the window, and the most it sends at once.
    public var total_available: Double?
    public var limit: Double?

    private enum CodingKeys: String, CodingKey {
        case as_of, line, kind, sealed, card_schema, window, counts, cards, truncated, covered_from, total_available, limit
    }

    public init(as_of: String? = nil, line: String? = nil, sealed: Bool? = nil, window: JournalWindow? = nil,
                cards: [JournalCard] = []) {
        self.as_of = as_of
        self.line = line
        self.kind = "journal"
        self.sealed = sealed
        self.window = window
        self.cards = Self.unique(cards)
    }

    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        as_of = c.lenientString(.as_of)
        line = c.lenientString(.line)
        kind = c.lenientString(.kind)
        sealed = c.lenientBool(.sealed)
        card_schema = c.lenientString(.card_schema)
        window = try? c.decodeIfPresent(JournalWindow.self, forKey: .window)
        if let raw = try? c.decodeIfPresent([String: JournalNumber].self, forKey: .counts) {
            counts = raw.compactMapValues(\.value)
        }
        cards = Self.unique((try? c.decodeIfPresent([JournalCard].self, forKey: .cards)) ?? [])
        truncated = c.lenientBool(.truncated)
        covered_from = c.lenientString(.covered_from)
        total_available = c.lenientDouble(.total_available)
        limit = c.lenientDouble(.limit)
    }

    /// First card per id (the id is unique; a repeat is the same card twice), newest first.
    static func unique(_ cards: [JournalCard]) -> [JournalCard] {
        var seen = Set<String>()
        // An element that was not a card at all (null, a number) has nothing to show.
        return cards.filter { ($0.id != nil || $0.tau != nil || $0.coin != nil) && seen.insert($0.key).inserted }
            .sorted { ($0.tauMs ?? -.infinity) > ($1.tauMs ?? -.infinity) }
    }
}

/// The span the document covers (the last 7 days). Read as from / to, or start / end.
public nonisolated struct JournalWindow: Decodable, Equatable, Sendable {
    public var from: String?
    public var to: String?
    public var days: Double?

    private enum CodingKeys: String, CodingKey { case from, to, start, end, days }

    public init(from: String? = nil, to: String? = nil, days: Double? = nil) {
        self.from = from
        self.to = to
        self.days = days
    }

    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        from = c.lenientString(.from) ?? c.lenientString(.start)
        to = c.lenientString(.to) ?? c.lenientString(.end)
        days = c.lenientDouble(.days)
    }
}

// MARK: - Card

/// One 理由卡: what the shadow did to one coin's position at decision time `tau`, and why.
public nonisolated struct JournalCard: Decodable, Equatable, Sendable, Identifiable {
    public var id: String?
    /// Decision time, UTC (ISO 8601 text, or epoch seconds / milliseconds).
    public var tau: String?
    public var coin: String?
    public var book: String?
    /// Placeholder rehearsal data (frozen stand-in): shown as 演练.
    public var placeholder: Bool = false
    /// Sealed period: no return, P&L or IC on the card.
    public var sealed: Bool?
    public var action: JournalAction?
    public var chain: JournalChain?
    public var signals: JournalSignals?
    public var attribution: JournalAttribution?
    /// One sentence in Chinese, at most 160 characters.
    public var summary_zh: String?
    /// The trade this card belongs to (LivePosition.tradeId / BacktestTrade.id): exact matching when present.
    public var trade_id: String?
    /// The model that decided, and the orders the decision placed.
    public var model: String?
    public var order_ids: [String] = []

    /// `tau` in epoch milliseconds, nil when it cannot be read.
    public private(set) var tauMs: Double?

    private enum CodingKeys: String, CodingKey {
        case id, tau, coin, book, placeholder, sealed, action, chain, signals, attribution, summary_zh
        case trade_id, model, order_ids
    }

    public init(id: String?, tau: String?, coin: String?, book: String? = nil, placeholder: Bool = false,
                sealed: Bool? = nil, action: JournalAction? = nil, chain: JournalChain? = nil,
                signals: JournalSignals? = nil, attribution: JournalAttribution? = nil, summary_zh: String? = nil,
                trade_id: String? = nil, model: String? = nil, order_ids: [String] = []) {
        self.id = id
        self.tau = tau
        self.coin = coin
        self.book = book
        self.placeholder = placeholder
        self.sealed = sealed
        self.action = action
        self.chain = chain
        self.signals = signals
        self.attribution = attribution
        self.summary_zh = summary_zh
        self.trade_id = trade_id
        self.model = model
        self.order_ids = order_ids
        tauMs = tau.flatMap(JournalTime.milliseconds)
    }

    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        id = c.lenientString(.id)
        tau = c.lenientString(.tau)
        if let number = c.lenientDouble(.tau) {
            tauMs = JournalTime.milliseconds(epoch: number)
        } else {
            tauMs = tau.flatMap(JournalTime.milliseconds)
        }
        coin = c.lenientString(.coin)
        book = c.lenientString(.book)
        placeholder = c.lenientBool(.placeholder) ?? false
        sealed = c.lenientBool(.sealed)
        action = try? c.decodeIfPresent(JournalAction.self, forKey: .action)
        chain = try? c.decodeIfPresent(JournalChain.self, forKey: .chain)
        signals = try? c.decodeIfPresent(JournalSignals.self, forKey: .signals)
        attribution = try? c.decodeIfPresent(JournalAttribution.self, forKey: .attribution)
        summary_zh = c.lenientString(.summary_zh)
        trade_id = c.lenientString(.trade_id).flatMap { $0.isEmpty ? nil : $0 }
        model = c.lenientString(.model)
        order_ids = ((try? c.decodeIfPresent([JournalText].self, forKey: .order_ids)) ?? []).compactMap(\.value)
    }

    /// The id, or (for a card without one) coin, time and kind, so it can still be told apart and listed.
    public var key: String { id ?? [coin ?? "", tau ?? "", action?.kind ?? ""].joined(separator: "|") }

    /// Base asset of the card's coin ("BTC").
    public var base: String? { coin.map(TradeJournal.base).flatMap { $0.isEmpty ? nil : $0 } }

    /// The top factor contributions as sent (at most 5), largest first by size.
    public var topFactors: [JournalFactor] {
        Array((attribution?.top ?? []).filter { $0.name_zh != nil || $0.contribution != nil }.prefix(5))
            .sorted { abs($0.contribution ?? 0) > abs($1.contribution ?? 0) }
    }

    /// Risk-control tags (l3.tags), blanks dropped.
    public var tags: [String] {
        (chain?.l3?.tags ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

/// action: kind and the position weight before and after (fractions of equity, negative = short).
public nonisolated struct JournalAction: Decodable, Equatable, Sendable {
    public var kind: String?
    public var w_before: Double?
    public var w_after: Double?
    public var delta: Double?

    private enum CodingKeys: String, CodingKey { case kind, w_before, w_after, delta }

    public init(kind: String?, w_before: Double? = nil, w_after: Double? = nil, delta: Double? = nil) {
        self.kind = kind
        self.w_before = w_before
        self.w_after = w_after
        self.delta = delta
    }

    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        kind = c.lenientString(.kind)
        w_before = c.lenientDouble(.w_before)
        w_after = c.lenientDouble(.w_after)
        delta = c.lenientDouble(.delta)
    }

    /// The change in weight: `delta`, or after − before when only those came.
    public var change: Double? {
        if let delta { return delta }
        guard let w_before, let w_after else { return nil }
        return w_after - w_before
    }

    /// 开仓 / 加仓 / 减仓 / 平仓 / 反手, or the kind as sent.
    public var title: String { JournalAction.title(kind) }

    public static func title(_ kind: String?) -> String {
        let raw = (kind ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch raw.lowercased() {
        case "open": return "开仓"
        case "add": return "加仓"
        case "reduce": return "减仓"
        case "close": return "平仓"
        case "flip": return "反手"
        case "": return "调仓"
        default: return raw
        }
    }

    /// False when the weights show the card is about a position on the other side of `side` (a long trade's card
    /// must hold a long before or after: open / add / flip into it, reduce / close / flip out of it). Unknown
    /// weights agree.
    func agrees(with side: BacktestSide) -> Bool {
        let weights = [w_before, w_after].compactMap { $0 }.filter { abs($0) > 1e-9 }
        guard !weights.isEmpty else { return true }
        return weights.contains { ($0 > 0) == (side.sign > 0) }
    }

    /// The position after the card is on `side` (falls back to `agrees` without a non-zero w_after).
    func opens(_ side: BacktestSide) -> Bool {
        guard let after = w_after, abs(after) > 1e-9 else { return agrees(with: side) }
        return (after > 0) == (side.sign > 0)
    }

    /// The position before the card was on `side`. Without a non-zero w_before: an opening card is the next trade's,
    /// anything else falls back to `agrees`.
    func leaves(_ side: BacktestSide) -> Bool {
        guard let before = w_before, abs(before) > 1e-9 else {
            return (kind ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "open" && agrees(with: side)
        }
        return (before > 0) == (side.sign > 0)
    }

    /// Kinds that start a position, so a card for them may be decided shortly before the opening fill.
    var opensPosition: Bool {
        switch (kind ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "add", "reduce", "close": false
        default: true
        }
    }
}

/// chain: the decision's layers. l2.intent, l3.tags (risk adjustments, may be empty), env.clipped (cut by a hard limit).
public nonisolated struct JournalChain: Decodable, Equatable, Sendable {
    public var l2: Intent?
    public var l3: Adjustments?
    public var env: Environment?

    public init(l2: Intent? = nil, l3: Adjustments? = nil, env: Environment? = nil) {
        self.l2 = l2
        self.l3 = l3
        self.env = env
    }

    public nonisolated struct Intent: Decodable, Equatable, Sendable {
        public var intent: String?
        private enum CodingKeys: String, CodingKey { case intent }
        public init(intent: String?) { self.intent = intent }
        public init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            intent = c.lenientString(.intent)
        }
    }

    public nonisolated struct Adjustments: Decodable, Equatable, Sendable {
        public var tags: [String] = []
        private enum CodingKeys: String, CodingKey { case tags }
        public init(tags: [String]) { self.tags = tags }
        public init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            tags = ((try? c.decodeIfPresent([JournalText].self, forKey: .tags)) ?? []).compactMap(\.value)
        }
    }

    public nonisolated struct Environment: Decodable, Equatable, Sendable {
        public var clipped: Bool?
        private enum CodingKeys: String, CodingKey { case clipped }
        public init(clipped: Bool?) { self.clipped = clipped }
        public init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            clipped = c.lenientBool(.clipped)
        }
    }
}

/// signals.scores: each score's value and its cross-sectional rank (rank of n, e.g. 4 / 52).
public nonisolated struct JournalSignals: Decodable, Equatable, Sendable {
    public var scores: [JournalScore] = []
    private enum CodingKeys: String, CodingKey { case scores }
    public init(scores: [JournalScore]) { self.scores = scores }
    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        scores = (try? c.decodeIfPresent([JournalScore].self, forKey: .scores)) ?? []
    }
}

public nonisolated struct JournalScore: Decodable, Equatable, Sendable {
    public var name: String?
    public var value: Double?
    public var rank: Int?
    public var n: Int?

    private enum CodingKeys: String, CodingKey { case name, value, rank, n }

    public init(name: String?, value: Double? = nil, rank: Int? = nil, n: Int? = nil) {
        self.name = name
        self.value = value
        self.rank = rank
        self.n = n
    }

    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        name = c.lenientString(.name)
        value = c.lenientDouble(.value)
        rank = c.lenientDouble(.rank).flatMap(Self.count)
        n = c.lenientDouble(.n).flatMap(Self.count)
    }

    /// A whole number in a sane range; anything else (1e20, −5) is not a rank.
    static func count(_ value: Double) -> Int? {
        value >= 0 && value < 1e9 ? Int(value.rounded()) : nil
    }

    /// "4/52", or "—" without a rank.
    public var rankText: String {
        guard let rank else { return "—" }
        return n.map { "\(rank)/\($0)" } ?? "\(rank)"
    }
}

/// attribution: the top factors (name_zh, contribution; at most 5), each sub-strategy's share, and a reminder.
public nonisolated struct JournalAttribution: Decodable, Equatable, Sendable {
    public var top: [JournalFactor] = []
    public var by_sleeve: [JournalSleeve] = []
    public var note: String?

    private enum CodingKeys: String, CodingKey { case top, by_sleeve, note }

    public init(top: [JournalFactor] = [], by_sleeve: [JournalSleeve] = [], note: String? = nil) {
        self.top = top
        self.by_sleeve = by_sleeve
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        top = (try? c.decodeIfPresent([JournalFactor].self, forKey: .top)) ?? []
        by_sleeve = (try? c.decodeIfPresent([JournalSleeve].self, forKey: .by_sleeve)) ?? []
        note = c.lenientString(.note)
    }

    /// Shares as fractions (0–1): sent either as fractions or as percentages adding up to about 100.
    public var sleeveFractions: [(name: String, fraction: Double)] {
        let named = by_sleeve.compactMap { sleeve -> (String, Double)? in
            guard let name = sleeve.name, !name.isEmpty, let share = sleeve.share else { return nil }
            return (name, share)
        }
        let total = named.reduce(0) { $0 + abs($1.1) }
        let percent = total > 1.5
        return named.map { (name: $0.0, fraction: percent ? $0.1 / 100 : $0.1) }.sorted { $0.fraction > $1.fraction }
    }
}

public nonisolated struct JournalFactor: Decodable, Equatable, Sendable {
    public var name_zh: String?
    public var contribution: Double?

    private enum CodingKeys: String, CodingKey { case name_zh, contribution }

    public init(name_zh: String?, contribution: Double?) {
        self.name_zh = name_zh
        self.contribution = contribution
    }

    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        name_zh = c.lenientString(.name_zh)
        contribution = c.lenientDouble(.contribution)
    }
}

public nonisolated struct JournalSleeve: Decodable, Equatable, Sendable {
    public var name: String?
    public var share: Double?

    private enum CodingKeys: String, CodingKey { case name, share }

    public init(name: String?, share: Double?) {
        self.name = name
        self.share = share
    }

    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        name = c.lenientString(.name)
        share = c.lenientDouble(.share)
    }
}

// MARK: - Matching a trade

nonisolated extension TradeJournal {
    /// The shadow decides on 15-minute bars, so a decision can come up to two bars before the opening fill.
    public static let leadMilliseconds: Double = 30 * 60_000
    /// Clock differences between the shadow and the exchange.
    public static let lagMilliseconds: Double = 2 * 60_000
    /// How far back the relay keeps cards, and how many at most.
    public static let keepDays: Double = 7
    public static let maxCards = 2_000

    /// The base asset of a contract or coin, upper-cased: "BTCUSDT", "BTC-USDT-SWAP", "btc/usdt", "BTC" → "BTC";
    /// a multiplier contract keeps only the coin ("1000PEPEUSDT" → "PEPE").
    public static func base(_ symbol: String) -> String {
        var text = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let cut = text.firstIndex(where: { $0 == "-" || $0 == "/" || $0 == "_" || $0 == ":" }) {
            text = String(text[..<cut])
        }
        for quote in ["USDT", "USDC", "USD"] where text.count > quote.count && text.hasSuffix(quote) {
            text = String(text.dropLast(quote.count))
            break
        }
        for multiplier in ["1000000", "100000", "10000", "1000", "1M"] where text.hasPrefix(multiplier) {
            let rest = text.dropFirst(multiplier.count)
            if let first = rest.first, first.isLetter { return String(rest) }
        }
        return text
    }

    /// The cards of one trade, oldest first. Cards carrying this trade's `trade_id` are an exact match and, when
    /// there are any, the only ones returned. Otherwise cards without a trade_id are matched by coin, direction (when
    /// `side` and the card's weights say) and time: decided between shortly before the trade opened
    /// (`leadMilliseconds`, opening kinds only) and its close (or now, for an open position). A card naming another
    /// trade never attaches.
    public func cards(symbol: String, side: BacktestSide? = nil, tradeID: String? = nil, from start: Double,
                      to end: Double) -> [JournalCard] {
        if let tradeID, !tradeID.isEmpty {
            let exact = cards.filter { $0.trade_id == tradeID }
            if !exact.isEmpty { return exact.sorted { ($0.tauMs ?? 0) < ($1.tauMs ?? 0) } }
        }
        let coin = Self.base(symbol)
        guard !coin.isEmpty else { return [] }
        return cards.filter { card in
            guard card.trade_id == nil else { return false }
            guard card.base == coin, let t = card.tauMs, t <= end + Self.lagMilliseconds else { return false }
            if let side, let action = card.action {
                // Before the opening fill a card must open into this side; after the close it must leave it; in
                // between, any card holding this side belongs to the trade.
                let fits = t < start ? action.opens(side) : t > end ? action.leaves(side) : action.agrees(with: side)
                if !fits { return false }
            }
            if t >= start { return true }
            return t >= start - Self.leadMilliseconds && (card.action?.opensPosition ?? true)
        }
        .sorted { ($0.tauMs ?? 0) < ($1.tauMs ?? 0) }
    }

    /// True when the relay sent fewer cards than it holds for the window (the 2000-card cap): older cards are gone
    /// even though `window` still reaches back 7 days.
    public var isTruncated: Bool {
        if let truncated { return truncated }
        if let total_available { return total_available > Double(cards.count) }
        let cap = limit.flatMap { $0 >= 1 && $0 < 1e7 ? Int($0) : nil } ?? Self.maxCards
        if cards.count >= cap { return true }
        guard let total = counts["cards"] ?? counts["total"] else { return false }
        return total > Double(cards.count)
    }

    /// Start of the span the cards really cover: `window.from` (else 7 days before as_of), or the oldest card sent
    /// when the document was cut at the cap. nil when none can be read.
    public var keptSince: Double? {
        if let covered = covered_from.flatMap(JournalTime.milliseconds) { return covered }
        var since = window?.from.flatMap(JournalTime.milliseconds)
        if since == nil, let asOf = as_of.flatMap(JournalTime.milliseconds) {
            since = asOf - (window?.days ?? Self.keepDays) * 86_400_000
        }
        if isTruncated, let oldest = cards.last(where: { $0.tauMs != nil })?.tauMs {
            since = max(since ?? oldest, oldest)
        }
        return since
    }

    /// True when a trade that opened at `start` reaches back before the covered span (its first cards are gone).
    public func startsBeforeWindow(_ start: Double) -> Bool {
        guard let since = keptSince else { return false }
        return start < since
    }

    /// For a long list: the first card plus the newest `keep - 1`, in order, and how many were left out.
    public static func condensed(_ cards: [JournalCard], keep: Int = 6) -> (cards: [JournalCard], hidden: Int) {
        guard keep >= 2, cards.count > keep else { return (cards, 0) }
        return ([cards[0]] + cards.suffix(keep - 1), cards.count - keep)
    }

    /// Actions counted by kind, in the order 开仓 加仓 减仓 平仓 反手 (then any other kind): "开仓 1 · 加仓 12".
    public static func kindSummary(_ cards: [JournalCard]) -> String {
        let order = ["开仓", "加仓", "减仓", "平仓", "反手"]
        var counts: [String: Int] = [:]
        for card in cards { counts[card.action?.title ?? JournalAction.title(nil), default: 0] += 1 }
        let known = order.compactMap { title in counts[title].map { "\(title) \($0)" } }
        let others = counts.keys.filter { !order.contains($0) }.sorted().map { "\($0) \(counts[$0] ?? 0)" }
        return (known + others).joined(separator: " · ")
    }
}

// MARK: - Formatting

public nonisolated enum JournalFormat {
    /// A position weight as a signed percentage of equity: "+3.2%", "0%", "−1.5%".
    public static func weight(_ fraction: Double?) -> String {
        guard let fraction else { return "—" }
        if abs(fraction) < 0.000_05 { return "0%" }
        let text = String(format: "%.1f%%", abs(fraction) * 100)
        return (fraction > 0 ? "+" : "−") + text
    }

    /// A factor contribution or score, signed, with enough digits for small values.
    public static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        let size = abs(value)
        let text: String
        if size == 0 {
            return "0"
        } else if size >= 100 {
            text = String(format: "%.0f", size)
        } else if size >= 1 {
            text = String(format: "%.2f", size)
        } else if size >= 0.001 {
            text = String(format: "%.3f", size)
        } else {
            text = String(format: "%.1e", size)
        }
        return (value > 0 ? "+" : "−") + text
    }

    /// A share of the decision (0–1) as a whole percentage.
    public static func share(_ fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }

    /// The fixed reminder shown with the cards.
    public static let caution = "个例理由只用来理解模型的行为，不能当规律的证据"
    /// What the app says while the relay answers 404.
    public static let notOpen = "交易理由卡尚未开放"
}

// MARK: - Time

nonisolated enum JournalTime {
    /// ISO 8601 with or without fractional seconds; a time without a zone is UTC. Plain numbers are epoch time.
    static func milliseconds(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let number = Double(trimmed) { return milliseconds(epoch: number) }
        var iso = trimmed.replacingOccurrences(of: " ", with: "T")
        if let t = iso.firstIndex(of: "T") {
            let time = iso[iso.index(after: t)...]
            if !(time.hasSuffix("Z") || time.contains("+") || time.contains("-")) { iso += "Z" }
        }
        if let date = try? Date(iso, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date.timeIntervalSince1970 * 1_000
        }
        if let date = try? Date(iso, strategy: Date.ISO8601FormatStyle()) {
            return date.timeIntervalSince1970 * 1_000
        }
        return nil
    }

    /// Epoch seconds, milliseconds, microseconds or nanoseconds, told apart by size.
    static func milliseconds(epoch value: Double) -> Double? {
        guard value.isFinite, value > 0 else { return nil }
        if value > 1e17 { return value / 1_000_000 }
        if value > 1e14 { return value / 1_000 }
        if value > 1e11 { return value }
        return value * 1_000
    }
}

// MARK: - Lenient reading

/// A number that may arrive as a number, a numeric string or a bool; anything else reads as nil.
nonisolated struct JournalNumber: Decodable, Sendable {
    var value: Double?
    init(from decoder: Decoder) throws {
        guard let c = try? decoder.singleValueContainer() else { return }
        if let number = try? c.decode(Double.self) {
            value = number
        } else if let text = try? c.decode(String.self) {
            value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

/// Text that may arrive as a string or a number; anything else reads as nil.
nonisolated struct JournalText: Decodable, Sendable {
    var value: String?
    init(from decoder: Decoder) throws {
        guard let c = try? decoder.singleValueContainer() else { return }
        if let text = try? c.decode(String.self) {
            value = text
        } else if let number = try? c.decode(Double.self) {
            value = number == number.rounded() && abs(number) < 1e15 ? String(Int64(number)) : String(number)
        } else if let flag = try? c.decode(Bool.self) {
            value = flag ? "true" : "false"
        }
    }
}

extension KeyedDecodingContainer {
    nonisolated func lenientString(_ key: Key) -> String? {
        (try? decodeIfPresent(JournalText.self, forKey: key))?.value
    }

    nonisolated func lenientDouble(_ key: Key) -> Double? {
        guard let value = (try? decodeIfPresent(JournalNumber.self, forKey: key))?.value, value.isFinite else { return nil }
        return value
    }

    nonisolated func lenientBool(_ key: Key) -> Bool? {
        if let flag = try? decodeIfPresent(Bool.self, forKey: key) { return flag }
        if let number = try? decodeIfPresent(Double.self, forKey: key) { return number != 0 }
        switch (try? decodeIfPresent(String.self, forKey: key))?.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }
}
