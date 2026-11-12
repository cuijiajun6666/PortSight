//
//  JournalBrowser.swift
//  PortSightKit
//
//  What the 理由卡 page (交易 · 理由卡, iOS and Mac) does with a TradeJournal: filter by coin, sub-strategy (sleeve)
//  and action kind; group the list by decision round (the shadow decides every 15 minutes, often for dozens of coins
//  at once); and count actions per day and per coin for the summary views. Counts only: nothing here is a result
//  (no return, P&L or IC), so all of it may be shown while the cards are sealed.
//

import Foundation

/// The page's filters; nil means any.
public nonisolated struct JournalFilter: Equatable, Hashable, Sendable {
    /// Base asset ("BTC"), as TradeJournal.base gives it.
    public var coin: String?
    /// A sleeve name from attribution.by_sleeve: the card must give that sleeve a share.
    public var sleeve: String?
    /// An action kind key (JournalAction.kindKey: "open", "add", …).
    public var kind: String?
    /// Start of a day (epoch milliseconds) in the page's calendar; the card's tau must fall in that day.
    public var day: Double?
    /// The card's book (which account the decision was for).
    public var book: String?

    public init(coin: String? = nil, sleeve: String? = nil, kind: String? = nil, day: Double? = nil, book: String? = nil) {
        self.book = book
        self.coin = coin
        self.sleeve = sleeve
        self.kind = kind
        self.day = day
    }

    public var isEmpty: Bool { coin == nil && sleeve == nil && kind == nil && day == nil && book == nil }

    public func matches(_ card: JournalCard, calendar: Calendar = .current) -> Bool {
        if let coin, card.base != coin { return false }
        if let sleeve, !card.sleeveNames.contains(sleeve) { return false }
        if let kind, (card.action?.kindKey ?? "") != kind { return false }
        if let book, card.book != book { return false }
        if let day {
            guard let t = card.tauMs else { return false }
            if JournalBrowser.dayStart(t, calendar: calendar) != day { return false }
        }
        return true
    }
}

/// Actions counted by kind.
public nonisolated struct JournalKindCounts: Equatable, Sendable {
    public private(set) var counts: [String: Int] = [:]
    public private(set) var total = 0

    public init() {}

    public init(_ cards: [JournalCard]) {
        for card in cards { add(card) }
    }

    public mutating func add(_ card: JournalCard) {
        counts[card.action?.kindKey ?? "", default: 0] += 1
        total += 1
    }

    public func count(_ kind: String) -> Int { counts[kind] ?? 0 }

    /// "开仓 1 · 加仓 12 · 减仓 3", known kinds first, as TradeJournal.kindSummary.
    public var summary: String {
        let known = JournalAction.kindOrder.compactMap { key in counts[key].map { JournalAction.title(key) + " \($0)" } }
        let others = counts.keys.filter { !JournalAction.kindOrder.contains($0) }.sorted()
            .map { JournalAction.title($0) + " \(counts[$0] ?? 0)" }
        return (known + others).joined(separator: " · ")
    }
}

/// One decision round: every card decided at the same tau (one 15-minute bar, often many coins).
public nonisolated struct JournalRound: Identifiable, Equatable, Sendable {
    public let tauMs: Double?
    /// The tau text, for a round whose time could not be read.
    public let tau: String?
    public let cards: [JournalCard]

    public var id: String { tauMs.map { String(Int64($0)) } ?? (tau ?? "") }
    public var coins: Int { Set(cards.compactMap(\.base)).count }
    public var kinds: JournalKindCounts { JournalKindCounts(cards) }
}

/// One day of cards in the page's calendar.
public nonisolated struct JournalDaySummary: Identifiable, Equatable, Sendable {
    /// Start of the day, epoch milliseconds.
    public let dayStart: Double
    public let kinds: JournalKindCounts
    /// Coins with at least one card, and decision rounds, that day.
    public let coins: Int
    public let rounds: Int

    public var id: Double { dayStart }
    public var total: Int { kinds.total }
}

/// One coin's cards.
public nonisolated struct JournalCoinSummary: Identifiable, Equatable, Sendable {
    public let coin: String
    public let kinds: JournalKindCounts
    /// The newest decision for this coin, epoch milliseconds.
    public let latest: Double?
    /// The newest card's weight after the decision (the position the shadow wanted then).
    public let latestWeight: Double?

    public var id: String { coin }
    public var total: Int { kinds.total }
}

public nonisolated enum JournalBrowser {
    /// Start of the day holding `milliseconds` in `calendar`.
    public static func dayStart(_ milliseconds: Double, calendar: Calendar = .current) -> Double {
        calendar.startOfDay(for: Date(milliseconds: milliseconds)).timeIntervalSince1970 * 1_000
    }

    /// Coins with their card counts, most first (then by name).
    public static func coins(in cards: [JournalCard]) -> [(coin: String, count: Int)] {
        tally(cards.compactMap(\.base))
    }

    /// Sleeve names with the number of cards that give them a share, most first.
    public static func sleeves(in cards: [JournalCard]) -> [(name: String, count: Int)] {
        tally(cards.flatMap { Array(Set($0.sleeveNames)) }).map { (name: $0.coin, count: $0.count) }
    }

    /// Books (accounts) with their card counts, most first.
    public static func books(in cards: [JournalCard]) -> [(book: String, count: Int)] {
        tally(cards.compactMap(\.book)).map { (book: $0.coin, count: $0.count) }
    }

    /// Kinds present, in the order 开仓 加仓 减仓 平仓 反手, then any other kind.
    public static func kinds(in cards: [JournalCard]) -> [(kind: String, title: String, count: Int)] {
        let counts = JournalKindCounts(cards)
        let present = Array(counts.counts.keys)
        let ordered = JournalAction.kindOrder.filter(present.contains) + present.filter { !JournalAction.kindOrder.contains($0) }.sorted()
        return ordered.map { (kind: $0, title: JournalAction.title($0), count: counts.count($0)) }
    }

    /// Cards passing `filter`, newest first.
    public static func filtered(_ cards: [JournalCard], _ filter: JournalFilter, calendar: Calendar = .current) -> [JournalCard] {
        filter.isEmpty ? cards : cards.filter { filter.matches($0, calendar: calendar) }
    }

    /// The cards by decision round, newest round first; inside a round by coin.
    public static func rounds(_ cards: [JournalCard]) -> [JournalRound] {
        var order: [String] = []
        var groups: [String: [JournalCard]] = [:]
        for card in cards {
            let key = card.tauMs.map { String(Int64($0)) } ?? ("?" + (card.tau ?? ""))
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(card)
        }
        return order.map { key in
            let members = (groups[key] ?? []).sorted { ($0.base ?? "", $0.key) < ($1.base ?? "", $1.key) }
            return JournalRound(tauMs: members.first?.tauMs, tau: members.first?.tau, cards: members)
        }
        .sorted { ($0.tauMs ?? -.infinity) > ($1.tauMs ?? -.infinity) }
    }

    /// Counts per day, newest day first. Cards without a readable time are left out.
    public static func days(_ cards: [JournalCard], calendar: Calendar = .current) -> [JournalDaySummary] {
        var groups: [Double: [JournalCard]] = [:]
        for card in cards {
            guard let t = card.tauMs else { continue }
            groups[dayStart(t, calendar: calendar), default: []].append(card)
        }
        return groups.map { day, members in
            JournalDaySummary(dayStart: day, kinds: JournalKindCounts(members),
                              coins: Set(members.compactMap(\.base)).count,
                              rounds: Set(members.compactMap(\.tauMs)).count)
        }
        .sorted { $0.dayStart > $1.dayStart }
    }

    /// Counts per coin, most cards first (then by name).
    public static func coinSummaries(_ cards: [JournalCard]) -> [JournalCoinSummary] {
        var groups: [String: [JournalCard]] = [:]
        for card in cards {
            guard let coin = card.base else { continue }
            groups[coin, default: []].append(card)
        }
        return groups.map { coin, members in
            let newest = members.max { ($0.tauMs ?? -.infinity) < ($1.tauMs ?? -.infinity) }
            return JournalCoinSummary(coin: coin, kinds: JournalKindCounts(members), latest: newest?.tauMs,
                                      latestWeight: newest?.action?.w_after)
        }
        .sorted { ($0.total, $1.coin) > ($1.total, $0.coin) }
    }

    private static func tally(_ values: [String]) -> [(coin: String, count: Int)] {
        var counts: [String: Int] = [:]
        for value in values where !value.isEmpty { counts[value, default: 0] += 1 }
        return counts.map { (coin: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.coin) > ($1.count, $0.coin) }
    }
}

nonisolated extension JournalCard {
    /// Names of the sleeves this card gives a share (attribution.by_sleeve), blanks dropped.
    public var sleeveNames: [String] {
        (attribution?.by_sleeve ?? []).compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

nonisolated extension JournalAction {
    /// The kinds in display order.
    public static let kindOrder = ["open", "add", "reduce", "close", "flip"]

    /// The kind as a filter key: trimmed and lower-cased ("" when missing).
    public var kindKey: String { (kind ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}

nonisolated extension TradeJournal {
    /// Said on the page when the relay cut the list: how many were sent of how many.
    public var truncationNote: String? {
        guard isTruncated else { return nil }
        if let total = total_available, total > Double(cards.count) {
            return "服务器只发了最近 \(cards.count) 张（这段时间共 \(Int(min(total, 1e9))) 张），更早的卡没有列出。"
        }
        return "服务器只发了最近 \(cards.count) 张，更早的卡没有列出。"
    }

    /// as_of in epoch milliseconds, nil when it cannot be read.
    public var asOfMilliseconds: Double? { as_of.flatMap(JournalTime.milliseconds) }
}
