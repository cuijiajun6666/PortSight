//
//  IBKRActivity.swift
//  PortSightKit
//
//  The personal IBKR account's activity from the Mac mini (GET /ibkr/activity, read only): fills (成交), orders
//  (委托, every status change), position changes (realtime only) and cash movements (资金流水: 入金 / 出金 / 分红 /
//  利息 / 费用 / 税). History comes from IBKR Flex reports (source "flex"), new events live (source "realtime").
//
//  Reading: the first GET returns the latest 500 with `next_cursor` (for what comes later) and `before` (for older
//  pages; null = no more). GET /ibkr/heartbeat every 10 s says `activity_seq`; when it grows, GET ?cursor=
//  fetches only what is new (again while has_more). Everything is kept on disk and de-duplicated by id, and lists
//  are ordered by `at` (UTC), never by seq: history was filled in after the fact. An order that is both in the
//  realtime feed and in Flex history may come twice with the same perm_id and status: it is shown once.
//

import Foundation
import Observation

// MARK: - Model

public nonisolated struct IBKRActivity: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case fill, order, position, cash, other
    }

    public var id: String
    /// Record number, only for paging (not for ordering).
    public var seq: Double?
    public var kind: Kind
    /// When it happened, UTC.
    public var at: String?
    /// realtime | flex.
    public var source: String?
    public var recorded_at: String?

    // fill / order
    public var symbol: String?
    public var sec_type: String?
    /// BUY | SELL.
    public var side: String?
    public var quantity: Double?
    public var price: Double?
    public var commission: Double?
    public var commission_currency: String?
    public var currency: String?
    public var exec_id: String?
    public var order_ref: String?
    public var perm_id: String?

    // order
    /// submitted | modified | partially_filled | filled | cancelled | rejected | inactive.
    public var status: String?
    public var order_type: String?
    public var limit_price: Double?
    public var filled: Double?
    public var remaining: Double?

    // position
    public var con_id: String?
    public var old_quantity: Double?
    public var new_quantity: Double?

    // cash
    /// deposit | withdrawal | dividend | interest | fee | tax | other.
    public var type: String?
    /// Positive in, negative out.
    public var amount: Double?
    public var description: String?

    /// The relay withdrew this record (e.g. a position change reported while the gateway was still loading the
    /// account): it is removed from the device and never shown.
    public var void: Bool?
    public var void_reason: String?

    private enum CodingKeys: String, CodingKey {
        case id, seq, kind, at, source, recorded_at, symbol, sec_type, side, quantity, price, commission,
             commission_currency, currency, exec_id, order_ref, perm_id, status, order_type, limit_price, filled,
             remaining, con_id, old_quantity, new_quantity, type, amount, description, void, void_reason
    }

    public var isVoid: Bool { void == true }

    public init(id: String, kind: Kind, at: String? = nil, source: String? = "realtime", seq: Double? = nil,
                symbol: String? = nil, side: String? = nil, quantity: Double? = nil, price: Double? = nil,
                commission: Double? = nil, currency: String? = "USD", perm_id: String? = nil, status: String? = nil,
                order_type: String? = nil, limit_price: Double? = nil, filled: Double? = nil, remaining: Double? = nil,
                old_quantity: Double? = nil, new_quantity: Double? = nil, type: String? = nil, amount: Double? = nil,
                description: String? = nil, sec_type: String? = "STK") {
        self.id = id
        self.kind = kind
        self.at = at
        self.source = source
        self.seq = seq
        self.symbol = symbol
        self.side = side
        self.quantity = quantity
        self.price = price
        self.commission = commission
        self.currency = currency
        self.perm_id = perm_id
        self.status = status
        self.order_type = order_type
        self.limit_price = limit_price
        self.filled = filled
        self.remaining = remaining
        self.old_quantity = old_quantity
        self.new_quantity = new_quantity
        self.type = type
        self.amount = amount
        self.description = description
        self.sec_type = sec_type
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientString(.id), !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "activity without id")
        }
        self.id = id
        seq = c.lenientDouble(.seq)
        kind = c.lenientString(.kind).flatMap { Kind(rawValue: $0.lowercased()) } ?? .other
        at = c.lenientString(.at)
        source = c.lenientString(.source)
        recorded_at = c.lenientString(.recorded_at)
        symbol = c.lenientString(.symbol).flatMap { $0.isEmpty ? nil : $0 }
        sec_type = c.lenientString(.sec_type)
        side = c.lenientString(.side)
        quantity = c.lenientDouble(.quantity)
        price = c.lenientDouble(.price)
        commission = c.lenientDouble(.commission)
        commission_currency = c.lenientString(.commission_currency)
        currency = c.lenientString(.currency)
        exec_id = c.lenientString(.exec_id)
        order_ref = c.lenientString(.order_ref)
        perm_id = c.lenientString(.perm_id).flatMap { $0.isEmpty || $0 == "0" ? nil : $0 }
        status = c.lenientString(.status)
        order_type = c.lenientString(.order_type)
        limit_price = c.lenientDouble(.limit_price)
        filled = c.lenientDouble(.filled)
        remaining = c.lenientDouble(.remaining)
        con_id = c.lenientString(.con_id)
        old_quantity = c.lenientDouble(.old_quantity)
        new_quantity = c.lenientDouble(.new_quantity)
        type = c.lenientString(.type)
        amount = c.lenientDouble(.amount)
        description = c.lenientString(.description).flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
        }
        void = c.lenientBool(.void)
        void_reason = c.lenientString(.void_reason)
    }

    // MARK: Reading

    public var date: Date? { at.flatMap(JournalTime.milliseconds).map { Date(timeIntervalSince1970: $0 / 1_000) } }
    public var isRealtime: Bool { source?.lowercased() == "realtime" }
    public var isBuy: Bool { side?.uppercased() == "BUY" || side?.uppercased() == "BOT" }

    /// 买入 / 卖出.
    public var sideTitle: String? {
        switch side?.uppercased() {
        case "BUY", "BOT": "买入"
        case "SELL", "SLD": "卖出"
        default: nil
        }
    }

    /// The order's status in Chinese.
    public var statusTitle: String? {
        switch status?.lowercased() {
        case "submitted": "已提交"
        case "modified": "已修改"
        case "partially_filled": "部分成交"
        case "filled": "已成交"
        case "cancelled", "canceled": "已撤单"
        case "rejected": "被拒绝"
        case "inactive": "未生效"
        case let other?: other
        case nil: nil
        }
    }

    /// The order is done with (filled, cancelled, rejected or inactive).
    public var isFinal: Bool {
        ["filled", "cancelled", "canceled", "rejected", "inactive"].contains(status?.lowercased() ?? "")
    }

    /// 入金 / 出金 / 分红 / 利息 / 费用 / 税 / 其他.
    public var cashTitle: String {
        IBKRCashType(type).title
    }

    /// Fill value (quantity × price), signed: money out for a buy, in for a sell.
    public var signedValue: Double? {
        guard let quantity, let price else { return nil }
        let value = abs(quantity) * price
        return isBuy ? -value : value
    }

    /// 股 for stocks and ETFs, 张 for options, 手 for futures; nothing for currencies (AUD.USD), crypto and bonds.
    public var unit: String {
        switch sec_type?.uppercased() {
        case "OPT", "FOP": "张"
        case "FUT": "手"
        case "CASH", "CRYPTO", "BOND", "CFD", "CMDTY": ""
        default: "股"
        }
    }

    /// 「10 股」, 「2 张」, or just 「4.8906」 for a currency.
    public func quantityWithUnit(_ value: Double?) -> String {
        let text = IBKRActivity.quantityText(value)
        return unit.isEmpty || value == nil ? text : text + " " + unit
    }

    /// One line: 「买入 AAPL」, 「AAPL 买入委托 · 已成交」, 「AAPL 持仓 10 → 15」, 「分红 · SPY」.
    public var title: String {
        let name = symbol ?? "—"
        switch kind {
        case .fill: return (sideTitle ?? "成交") + " " + name
        case .order: return name + " " + (sideTitle ?? "") + "委托" + (statusTitle.map { " · " + $0 } ?? "")
        case .position: return name + " 持仓变化"
        case .cash: return cashTitle + (symbol.map { " · " + $0 } ?? "")
        case .other: return symbol ?? "账户活动"
        }
    }

    /// The figures under the title.
    public var detail: String {
        switch kind {
        case .fill:
            var parts = [quantityWithUnit(quantity) + " × " + IBKRActivity.money(price, currency)]
            if let commission, commission != 0 {
                parts.append("佣金 " + IBKRActivity.money(abs(commission), commission_currency ?? currency))
            }
            return parts.joined(separator: " · ")
        case .order:
            var parts: [String] = []
            if let order_type { parts.append(IBKRActivity.orderTypeTitle(order_type)) }
            if let limit_price { parts.append("限价 " + IBKRActivity.money(limit_price, currency)) }
            if let quantity { parts.append(quantityWithUnit(quantity)) }
            if let filled, filled > 0 { parts.append("已成交 " + IBKRActivity.quantityText(filled)) }
            if let remaining, remaining > 0, !isFinal { parts.append("剩余 " + IBKRActivity.quantityText(remaining)) }
            return parts.isEmpty ? (statusTitle ?? "委托") : parts.joined(separator: " · ")
        case .position:
            return IBKRActivity.quantityText(old_quantity) + " → " + IBKRActivity.quantityText(new_quantity)
        case .cash:
            return description ?? cashTitle
        case .other:
            return description ?? ""
        }
    }

    public static func orderTypeTitle(_ type: String) -> String {
        switch type.uppercased() {
        case "LMT": "限价单"
        case "MKT": "市价单"
        case "STP": "止损单"
        case "STP LMT", "STP_LMT": "止损限价单"
        case "TRAIL": "跟踪止损单"
        case "MOC": "收盘市价单"
        case "LOC": "收盘限价单"
        default: type
        }
    }

    public static func quantityText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value == value.rounded() ? String(Int64(value)) : value.formatted(.number.precision(.fractionLength(0...4)))
    }

    public static func money(_ value: Double?, _ currency: String?) -> String {
        guard let value else { return "—" }
        let text = abs(value).formatted(.number.precision(.fractionLength(2)).grouping(.automatic))
        let sign = value < 0 ? "-" : ""
        switch currency?.uppercased() {
        case nil, "USD": return sign + "$" + text
        case "HKD": return sign + "HK$" + text
        case "CNH", "CNY": return sign + "¥" + text
        case "AUD": return sign + "A$" + text
        case let code?: return sign + text + " " + code
        }
    }
}

/// The kinds of cash movement, with their Chinese names.
public nonisolated enum IBKRCashType: String, CaseIterable, Sendable, Identifiable {
    case deposit, withdrawal, dividend, interest, fee, tax, other

    public init(_ raw: String?) { self = IBKRCashType(rawValue: raw?.lowercased() ?? "") ?? .other }

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .deposit: "入金"
        case .withdrawal: "出金"
        case .dividend: "分红"
        case .interest: "利息"
        case .fee: "费用"
        case .tax: "税"
        case .other: "其他"
        }
    }

    public var icon: String {
        switch self {
        case .deposit: "arrow.down.to.line"
        case .withdrawal: "arrow.up.to.line"
        case .dividend: "dollarsign.arrow.circlepath"
        case .interest: "percent"
        case .fee: "creditcard"
        case .tax: "building.columns"
        case .other: "ellipsis.circle"
        }
    }
}

/// One page of GET /ibkr/activity.
public nonisolated struct IBKRActivityPage: Decodable, Sendable {
    public var items: [IBKRActivity] = []
    /// For GET ?cursor=: what comes after this page.
    public var next_cursor: String?
    /// For GET ?before=: older pages; nil = this is the oldest.
    public var before: String?
    /// More is waiting after `next_cursor`.
    public var has_more: Bool?

    private enum CodingKeys: String, CodingKey { case items, activities, activity, events, records, data, next_cursor, before, has_more }

    public init(items: [IBKRActivity], next_cursor: String? = nil, before: String? = nil, has_more: Bool? = nil) {
        self.items = items
        self.next_cursor = next_cursor
        self.before = before
        self.has_more = has_more
    }

    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        let lists = [CodingKeys.items, .activities, .activity, .events, .records, .data].lazy.compactMap {
            try? c.decodeIfPresent([Lossy<IBKRActivity>].self, forKey: $0)
        }
        items = (lists.first ?? []).compactMap(\.value)
        next_cursor = c.lenientString(.next_cursor).flatMap { $0.isEmpty ? nil : $0 }
        before = c.lenientString(.before).flatMap { $0.isEmpty ? nil : $0 }
        has_more = c.lenientBool(.has_more)
    }
}

/// GET /ibkr/heartbeat: the latest activity record number (and whatever else the relay adds).
public nonisolated struct IBKRHeartbeat: Decodable, Sendable {
    public var activity_seq: Double?

    private enum CodingKeys: String, CodingKey { case activity_seq }

    public init(activity_seq: Double?) { self.activity_seq = activity_seq }

    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        activity_seq = c.lenientDouble(.activity_seq)
    }
}

/// What is kept on disk between launches.
public nonisolated struct IBKRActivityLog: Codable, Equatable, Sendable {
    public var items: [IBKRActivity]
    public var nextCursor: String?
    public var olderCursor: String?
    public var reachedStart: Bool
    public var lastSeq: Double?

    public init(items: [IBKRActivity] = [], nextCursor: String? = nil, olderCursor: String? = nil,
                reachedStart: Bool = false, lastSeq: Double? = nil) {
        self.items = items
        self.nextCursor = nextCursor
        self.olderCursor = olderCursor
        self.reachedStart = reachedStart
        self.lastSeq = lastSeq
    }
}

// MARK: - Lists

/// One order's life: its status changes in time order, and the fills that belong to it.
public nonisolated struct IBKROrderHistory: Identifiable, Sendable {
    /// perm_id (or the activity id when there is none).
    public var id: String
    public var symbol: String?
    public var side: String?
    /// Oldest first; each status at most once.
    public var steps: [IBKRActivity]
    public var fills: [IBKRActivity]

    public var latest: IBKRActivity? { steps.last }
    public var date: Date? { steps.last?.date ?? fills.last?.date }
    public var isOpen: Bool { !(latest?.isFinal ?? true) }

    /// Average fill price (or the limit price while nothing filled).
    public var averagePrice: Double? {
        let quantity = fills.reduce(0) { $0 + abs($1.quantity ?? 0) }
        guard quantity > 0 else { return steps.last(where: { $0.limit_price != nil })?.limit_price }
        return fills.reduce(0) { $0 + abs($1.quantity ?? 0) * ($1.price ?? 0) } / quantity
    }

    public var quantity: Double? { steps.last(where: { $0.quantity != nil })?.quantity ?? (fills.isEmpty ? nil : fills.reduce(0) { $0 + abs($1.quantity ?? 0) }) }

    /// A record of this order that says what it trades (its unit: 股 / 张 / 手 / none).
    public var unitSource: IBKRActivity? { steps.last(where: { $0.sec_type != nil }) ?? fills.first ?? steps.last }

    /// 「10 股」 for this order's instrument.
    public func quantityWithUnit(_ value: Double?) -> String {
        unitSource?.quantityWithUnit(value) ?? IBKRActivity.quantityText(value)
    }

    /// Shares filled so far.
    public var filledQuantity: Double {
        let fromFills = fills.reduce(0) { $0 + abs($1.quantity ?? 0) }
        return max(fromFills, steps.compactMap(\.filled).max() ?? 0)
    }

    public var isBuy: Bool {
        let direction = (latest?.side ?? side)?.uppercased()
        return direction == "BUY" || direction == "BOT"
    }

    /// 「买入 AAPL」.
    public var title: String { (isBuy ? "买入" : "卖出") + " " + (symbol ?? "—") }

    /// 「已成交 · 10 股 · 均价 $225.50」.
    public var detail: String {
        var parts: [String] = []
        if let status = latest?.statusTitle { parts.append(status) }
        if let quantity { parts.append(unitSource?.quantityWithUnit(abs(quantity)) ?? IBKRActivity.quantityText(abs(quantity))) }
        let filled = filledQuantity
        if let quantity, filled > 0, filled < abs(quantity) { parts.append("已成交 " + IBKRActivity.quantityText(filled)) }
        if let price = averagePrice {
            parts.append((fills.isEmpty ? "限价 " : "均价 ") + IBKRActivity.money(price, latest?.currency ?? fills.first?.currency))
        }
        return parts.joined(separator: " · ")
    }
}

/// One line of the activity list: an order (all its status changes and fills folded into one) or a single
/// record (a fill without a known order, a position change, a cash movement).
public nonisolated enum IBKRTimelineEntry: Identifiable, Sendable {
    case order(IBKROrderHistory)
    case record(IBKRActivity)

    public var id: String {
        switch self {
        case .order(let history): "order:" + history.id
        case .record(let item): item.id
        }
    }

    public var date: Date? {
        switch self {
        case .order(let history): history.date
        case .record(let item): item.date
        }
    }

    public var symbol: String? {
        switch self {
        case .order(let history): history.symbol
        case .record(let item): item.symbol
        }
    }

    public var title: String {
        switch self {
        case .order(let history): history.title
        case .record(let item): item.title
        }
    }

    public var detail: String {
        switch self {
        case .order(let history): history.detail
        case .record(let item): item.detail
        }
    }
}

/// Which records the activity list shows.
public nonisolated enum IBKRActivityFilter: String, CaseIterable, Identifiable, Sendable {
    /// Everything.
    case all = "全部"
    /// Orders and fills (交易记录).
    case trades = "交易"
    /// Cash movements (资金流水).
    case cash = "资金"
    /// Position changes (realtime only).
    case positions = "持仓"

    public var id: String { rawValue }

    func includes(_ kind: IBKRActivity.Kind) -> Bool {
        switch self {
        case .all: true
        case .trades: kind == .fill || kind == .order
        case .cash: kind == .cash
        case .positions: kind == .position
        }
    }
}

public nonisolated enum IBKRActivityList {
    /// Newest first by `at` (then by seq), one entry per id, and an order that came from both the realtime feed and
    /// Flex history (same perm_id and status) only once — the realtime one, or the first read.
    public static func visible(_ items: [IBKRActivity]) -> [IBKRActivity] {
        var seenIDs = Set<String>()
        var seenOrders = Set<String>()
        var result: [IBKRActivity] = []
        // Realtime first, so it is the one kept when an order is in both. Withdrawn records never show.
        for item in items.sorted(by: { ($0.isRealtime ? 0 : 1) < ($1.isRealtime ? 0 : 1) }) where !item.isVoid
            && !IBKRActivityStore.withdrawn.contains(item.id) {
            guard seenIDs.insert(item.id).inserted else { continue }
            if item.kind == .order, let perm = item.perm_id {
                let key = perm + "|" + (item.status?.lowercased() ?? "")
                guard seenOrders.insert(key).inserted else { continue }
            }
            result.append(item)
        }
        return sorted(result)
    }

    /// Newest first by time; equal times by record number.
    public static func sorted(_ items: [IBKRActivity]) -> [IBKRActivity] {
        items.sorted { a, b in
            let ta = a.date?.timeIntervalSince1970 ?? -.infinity, tb = b.date?.timeIntervalSince1970 ?? -.infinity
            if ta != tb { return ta > tb }
            return (a.seq ?? 0) > (b.seq ?? 0)
        }
    }

    /// Fills and orders (the 交易记录 page), optionally for one symbol.
    public static func trades(_ items: [IBKRActivity], symbol: String? = nil) -> [IBKRActivity] {
        visible(items).filter { ($0.kind == .fill || $0.kind == .order) && matches($0, symbol) }
    }

    /// Cash movements (the 资金 page), optionally of one type.
    public static func cash(_ items: [IBKRActivity], type: IBKRCashType? = nil) -> [IBKRActivity] {
        visible(items).filter { $0.kind == .cash && (type == nil || IBKRCashType($0.type) == type) }
    }

    /// Sums per cash type (入金 positive, 出金 negative as received).
    public static func cashTotals(_ items: [IBKRActivity]) -> [IBKRCashType: Double] {
        var totals: [IBKRCashType: Double] = [:]
        for item in cash(items) { totals[IBKRCashType(item.type), default: 0] += item.amount ?? 0 }
        return totals
    }

    /// Every traded symbol, alphabetically (for the filter).
    public static func symbols(_ items: [IBKRActivity]) -> [String] {
        Array(Set(items.filter { $0.kind == .fill || $0.kind == .order }.compactMap { $0.symbol?.uppercased() })).sorted()
    }

    /// Orders by perm_id, newest first: each with its status steps (oldest first) and fills.
    public static func orders(_ items: [IBKRActivity], symbol: String? = nil) -> [IBKROrderHistory] {
        let shown = visible(items)
        var histories: [String: IBKROrderHistory] = [:]
        for item in shown where item.kind == .order && matches(item, symbol) {
            let key = item.perm_id ?? item.id
            histories[key, default: IBKROrderHistory(id: key, symbol: item.symbol, side: item.side, steps: [], fills: [])]
                .steps.append(item)
        }
        for item in shown where item.kind == .fill {
            guard let perm = item.perm_id, histories[perm] != nil else { continue }
            histories[perm]?.fills.append(item)
        }
        return histories.values.map { history in
            var history = history
            history.steps = Array(sorted(history.steps).reversed())
            history.fills = Array(sorted(history.fills).reversed())
            return history
        }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// The list as shown: newest first, each order one entry (its fills folded in), filtered by kind and by a
    /// search over symbol and text.
    public static func timeline(_ items: [IBKRActivity], filter: IBKRActivityFilter = .all,
                                search: String = "") -> [IBKRTimelineEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var entries: [IBKRTimelineEntry] = []
        let histories = filter.includes(.order) ? orders(items) : []
        let folded = Set(histories.flatMap { $0.fills.map(\.id) })
        entries += histories.map(IBKRTimelineEntry.order)
        for item in visible(items) where item.kind != .order && filter.includes(item.kind) && !folded.contains(item.id) {
            entries.append(.record(item))
        }
        if !query.isEmpty {
            entries = entries.filter { entry in
                [entry.symbol ?? "", entry.title, entry.detail].contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }
        return entries.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Timeline entries by local day, newest day first.
    public static func byDay(_ entries: [IBKRTimelineEntry], calendar: Calendar = .current) -> [(day: Date, entries: [IBKRTimelineEntry])] {
        var groups: [(day: Date, entries: [IBKRTimelineEntry])] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date ?? .distantPast)
            if let last = groups.indices.last, groups[last].day == day { groups[last].entries.append(entry) }
            else { groups.append((day, [entry])) }
        }
        return groups
    }

    /// Cash totals per type and currency (a currency's totals are never added to another's).
    public static func cashTotalsByCurrency(_ items: [IBKRActivity]) -> [(currency: String, totals: [IBKRCashType: Double])] {
        var byCurrency: [String: [IBKRCashType: Double]] = [:]
        for item in cash(items) {
            byCurrency[(item.currency ?? "USD").uppercased(), default: [:]][IBKRCashType(item.type), default: 0] += item.amount ?? 0
        }
        return byCurrency.sorted { $0.key == "USD" ? true : $1.key == "USD" ? false : $0.key < $1.key }
            .map { (currency: $0.key, totals: $0.value) }
    }

    /// One order's history by perm_id.
    public static func order(_ permID: String, in items: [IBKRActivity]) -> IBKROrderHistory? {
        orders(items).first { $0.id == permID }
    }

    /// Grouped by local day, newest day first (items keep their order).
    public static func byDay(_ items: [IBKRActivity], calendar: Calendar = .current) -> [(day: Date, items: [IBKRActivity])] {
        var groups: [(day: Date, items: [IBKRActivity])] = []
        for item in items {
            let day = calendar.startOfDay(for: item.date ?? .distantPast)
            if let last = groups.indices.last, groups[last].day == day { groups[last].items.append(item) }
            else { groups.append((day, [item])) }
        }
        return groups
    }

    /// 「今天」, 「昨天」, 「11月9日 周一」, or with the year when not this year.
    public static func dayTitle(_ day: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if day == .distantPast { return "时间未知" }
        if calendar.isDate(day, inSameDayAs: now) { return "今天" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "昨天"
        }
        let style = calendar.component(.year, from: day) == calendar.component(.year, from: now)
            ? Date.FormatStyle.dateTime.month().day().weekday(.abbreviated)
            : Date.FormatStyle.dateTime.year().month().day().weekday(.abbreviated)
        return day.formatted(style.locale(Locale(identifier: "zh_CN")))
    }

    private static func matches(_ item: IBKRActivity, _ symbol: String?) -> Bool {
        guard let symbol, !symbol.isEmpty else { return true }
        return item.symbol?.uppercased() == symbol.uppercased()
    }
}

// MARK: - Store

/// The activity kept on this device and how it is brought up to date. Read through the paired relay
/// (ServerStore.read); saved to disk after every change; dropped when the relay is unpaired or replaced.
@Observable
public final class IBKRActivityStore {
    public static let shared = IBKRActivityStore()

    public typealias Phase = RelayFeedStore<IBKRActivityLog>.Phase
    public typealias Reader = (RelayEndpoint, [URLQueryItem]) async throws -> Data

    /// Every record read so far (unordered; use `visible` / IBKRActivityList for lists).
    public private(set) var items: [IBKRActivity] = []
    public private(set) var phase: Phase = .idle
    /// When the activity was last brought up to date from the relay.
    public private(set) var readAt: Date?
    /// The items on screen are a saved copy (the last read failed or came from disk).
    public private(set) var isSaved = false
    /// No older page is left (the relay's `before` was null).
    public private(set) var reachedStart = false
    public private(set) var loadingOlder = false

    /// Heartbeat interval (and the shortest gap between automatic reads).
    public static let heartbeatInterval: TimeInterval = 10
    /// At most this many ?cursor= pages in one catch-up.
    static let pageLimit = 20

    @ObservationIgnored private var nextCursor: String?
    @ObservationIgnored private var olderCursor: String?
    @ObservationIgnored private var lastSeq: Double?
    @ObservationIgnored private var loadedFrom: String?
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var lastHeartbeat: Date?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private let read: Reader
    @ObservationIgnored private let currentBase: () -> String?
    @ObservationIgnored private let cacheName: String?

    /// Shortest gap between automatic reads and between heartbeats (tests use a longer one, so a busy machine cannot
    /// make them flaky).
    @ObservationIgnored private let minGap: TimeInterval

    public init(read: Reader? = nil, base: (() -> String?)? = nil, cacheName: String? = "ibkr_activity.json",
                minGap: TimeInterval = IBKRActivityStore.heartbeatInterval) {
        self.minGap = minGap
        self.read = read ?? { endpoint, query in try await ServerStore.shared.read(endpoint, query: query) }
        self.currentBase = base ?? {
            let server = ServerStore.shared
            return server.isPaired && RelayNotices.usesRelay ? server.baseURL : nil
        }
        self.cacheName = cacheName
        restore()
    }

    /// Fills, orders, position changes and cash, newest first, duplicates removed.
    public var visible: [IBKRActivity] { IBKRActivityList.visible(items) }

    // MARK: Reading

    /// Brings the activity up to date: the first page when nothing is kept yet, else only what is new.
    /// At most every 10 s unless forced (a push about a new fill or order forces it).
    public func refresh(force: Bool = false) async {
        await exclusive(force: force) { base in
            if self.nextCursor == nil && self.items.isEmpty {
                try await self.fetchFirst(base: base)
            } else {
                try await self.fetchNew(base: base)
            }
        }
    }

    /// GET /ibkr/heartbeat; when activity_seq grew, GET only what is new. At most one every 10 s however many pages
    /// poll at once (a pushed 订单 page over 动态), unless forced.
    public func heartbeat(force: Bool = false) async {
        if !force, let lastHeartbeat, Date.now.timeIntervalSince(lastHeartbeat) < minGap - 1 { return }
        lastHeartbeat = .now
        await exclusive(force: true) { base in
            let data = try await self.read(.ibkrHeartbeat, [])
            let seq = try JSONDecoder().decode(IBKRHeartbeat.self, from: data).activity_seq
            guard self.currentBase() == base else { return }
            if self.items.isEmpty && self.nextCursor == nil {
                try await self.fetchFirst(base: base)
            } else if let seq, seq > (self.lastSeq ?? -1) {
                try await self.fetchNew(base: base)
            }
            if let seq { self.lastSeq = max(self.lastSeq ?? seq, seq) }
            self.save(base: base)
        }
    }

    /// While a page that shows the activity is on screen and the app is in front: the heartbeat every 10 s.
    public func runPolling() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.heartbeatInterval))
            guard !Task.isCancelled else { return }
            await heartbeat()
        }
    }

    /// The next older page (GET ?before=), for scrolling to the end of the history.
    public func loadOlder() async {
        guard !reachedStart, !loadingOlder, let cursor = olderCursor else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        await exclusive(force: true) { base in
            let page = try await self.page([URLQueryItem(name: "before", value: cursor)])
            guard self.currentBase() == base else { return }
            self.merge(page.items)
            self.olderCursor = page.before
            self.reachedStart = page.before == nil
            self.save(base: base)
        }
    }

    /// Forgets everything (unpaired, or another relay) and its saved copy.
    public func reset() {
        running?.cancel()
        running = nil
        items = []
        phase = currentBase() == nil ? .unpaired : .idle
        readAt = nil
        isSaved = false
        reachedStart = false
        nextCursor = nil
        olderCursor = nil
        lastSeq = nil
        loadedFrom = nil
        lastAttempt = nil
        lastHeartbeat = nil
        if let url = cacheURL { try? FileManager.default.removeItem(at: url) }
    }

    /// For tests and previews.
    public func show(_ items: [IBKRActivity], reachedStart: Bool = true) {
        self.items = items
        self.reachedStart = reachedStart
        readAt = .now
        isSaved = false
        phase = .loaded
        loadedFrom = currentBase()
    }

    private func fetchFirst(base: String) async throws {
        let page = try await page([])
        guard currentBase() == base else { return }
        merge(page.items)
        nextCursor = page.next_cursor ?? nextCursor
        olderCursor = page.before
        reachedStart = page.before == nil
        if page.has_more == true, nextCursor != nil { try await fetchNew(base: base) }
        save(base: base)
    }

    private func fetchNew(base: String) async throws {
        guard let cursor = nextCursor else { return try await fetchFirst(base: base) }
        var current = cursor
        for _ in 0..<Self.pageLimit {
            let page = try await page([URLQueryItem(name: "cursor", value: current)])
            guard currentBase() == base else { return }
            merge(page.items)
            if let next = page.next_cursor { current = next }
            nextCursor = current
            guard page.has_more == true, page.next_cursor != nil, !page.items.isEmpty else { break }
        }
        save(base: base)
    }

    private func page(_ query: [URLQueryItem]) async throws -> IBKRActivityPage {
        let data = try await read(.ibkrActivity, query)
        if let message = RelayAvailability.unavailableMessage(data) { throw Unavailable(message: message) }
        return try JSONDecoder().decode(IBKRActivityPage.self, from: data)
    }

    private struct Unavailable: Error { var message: String? }

    /// Records the relay withdrew before it could flag them (11-12: two SIDU position changes 50443 → 0 → 50443
    /// reported while the gateway reconnected): dropped from saved copies too.
    nonisolated static let withdrawn: Set<String> = ["act:position:f02abc689d5f186d0f5a8893", "act:position:e8397223881dc8c75a2ec7ab"]

    private func merge(_ fresh: [IBKRActivity]) {
        guard !fresh.isEmpty else { return }
        var byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in fresh {
            // A withdrawn record (void) is deleted, not kept hidden.
            if item.isVoid { byID[item.id] = nil } else { byID[item.id] = item }
        }
        items = Array(byID.values).filter { !Self.withdrawn.contains($0.id) }
    }

    /// One read at a time; a read while another runs waits for it (and then skips unless forced).
    private func exclusive(force: Bool, _ body: @escaping (String) async throws -> Void) async {
        guard let base = currentBase() else {
            if phase != .unpaired { reset() }
            return
        }
        if let running {
            await running.value
            if !force { return }
        }
        if loadedFrom != nil, loadedFrom != base { reset() }
        if !force, let lastAttempt, Date.now.timeIntervalSince(lastAttempt) < minGap - 0.5 { return }
        lastAttempt = .now
        let task = Task {
            if self.items.isEmpty { self.phase = .loading }
            do {
                try await body(base)
                guard self.currentBase() == base else { return }
                self.loadedFrom = base
                self.readAt = .now
                self.isSaved = false
                self.phase = .loaded
            } catch {
                guard self.currentBase() == base else { return }
                self.fail(error)
            }
        }
        running = task
        await task.value
        if running == task { running = nil }
    }

    private func fail(_ error: Error) {
        if RelayAPI.isCancellation(error) {
            // Called off on this side: not a failure; the list stays and the next read may come at once.
            if phase == .loading { phase = items.isEmpty ? .idle : .loaded }
            lastAttempt = nil
            return
        }
        let next: Phase
        do {
            throw error
        } catch ServerError.http(404) {
            next = .notOpen
        } catch ServerError.unauthorized {
            next = .needsRepair
        } catch ServerError.notPaired, ServerError.invalidURL {
            next = .unpaired
        } catch ServerError.rateLimited {
            next = .rateLimited
        } catch ServerError.http(403) {
            next = .failed("服务器暂时拒绝了这项请求（403），稍后自动再试")
        } catch ServerError.http(let status) {
            next = .failed("服务器返回 \(status)")
        } catch let unavailable as Unavailable {
            next = .unavailable(unavailable.message)
        } catch is DecodingError {
            next = .failed("服务器返回的内容读不懂")
        } catch {
            next = .failed("连不上服务器（检查网络）")
        }
        if !items.isEmpty { isSaved = true }
        phase = next
    }

    // MARK: Disk

    private struct Saved: Codable {
        var base: String
        var readAt: Date?
        var log: IBKRActivityLog
    }

    private var cacheURL: URL? { cacheName.map { RelayCache.directory.appendingPathComponent($0) } }

    private func save(base: String) {
        guard let url = cacheURL else { return }
        let log = IBKRActivityLog(items: items, nextCursor: nextCursor, olderCursor: olderCursor,
                                  reachedStart: reachedStart, lastSeq: lastSeq)
        guard let data = try? JSONEncoder().encode(Saved(base: base, readAt: readAt ?? .now, log: log)) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func restore() {
        guard let url = cacheURL, let base = currentBase(), let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(Saved.self, from: data), saved.base == base else { return }
        items = saved.log.items.filter { !$0.isVoid && !Self.withdrawn.contains($0.id) }
        nextCursor = saved.log.nextCursor
        olderCursor = saved.log.olderCursor
        reachedStart = saved.log.reachedStart
        lastSeq = saved.log.lastSeq
        readAt = saved.readAt
        isSaved = true
        loadedFrom = base
        phase = .loaded
    }
}

// MARK: - As the pages' existing rows

extension IBKRActivity {
    /// As a row of the 动态 list.
    public var asDemoActivity: DemoActivity {
        let icon: String
        let category: String
        let amount: Double?
        switch kind {
        case .fill:
            icon = isBuy ? "arrow.down.left" : "arrow.up.right"
            category = "成交"
            amount = signedValue
        case .order:
            icon = "list.bullet.rectangle"
            category = "委托"
            amount = nil
        case .position:
            icon = "chart.bar.doc.horizontal"
            category = "持仓"
            amount = nil
        case .cash:
            let type = IBKRCashType(type)
            icon = type.icon
            category = type == .dividend ? "分红" : "资金"
            amount = self.amount
        case .other:
            icon = "circle"
            category = "系统"
            amount = self.amount
        }
        return DemoActivity(id: id, title: title, detail: detail, icon: icon,
                            time: RelayNotice.timeText(date, now: .now), owner: .personal, category: category,
                            amount: amount)
    }
}

extension IBKRTimelineEntry {
    /// As a row of the 动态 list / 最近动态 card.
    public var asDemoActivity: DemoActivity {
        switch self {
        case .record(let item):
            return item.asDemoActivity
        case .order(let history):
            let value = history.fills.reduce(0.0) { $0 + ($1.signedValue ?? 0) }
            return DemoActivity(id: id, title: history.title, detail: history.detail,
                                icon: history.isBuy ? "arrow.down.left" : "arrow.up.right",
                                time: RelayNotice.timeText(history.date, now: .now), owner: .personal, category: "成交",
                                amount: history.fills.isEmpty ? nil : value)
        }
    }
}

extension IBKROrderHistory {
    /// As a row of the 订单 page.
    public var asPortfolioOrder: PortfolioOrder? {
        guard let symbol, let latest else { return nil }
        let direction = (latest.side ?? side)?.uppercased()
        return PortfolioOrder(id: id, symbol: symbol, side: direction == "BUY" || direction == "BOT" ? .buy : .sell,
                              status: isOpen ? .pending : .completed, price: averagePrice ?? 0,
                              quantity: abs(quantity ?? 0), date: date ?? .distantPast,
                              orderStateText: latest.statusTitle)
    }
}

