//
//  IBKRModels.swift
//  PortSightKit
//
//  The personal IBKR account as the Mac mini sees it through IB Gateway (a read-only secondary user, read-only API:
//  nothing here or on the Mac mini can place an order). GET /ibkr/status says whether the gateway is logged in;
//  IBKR wants a fresh two-factor login every week, which the app can only ask the Mac mini to start
//  (POST /ibkr/reauth) and the user confirms in IBKR Mobile. GET /account carries the account itself in
//  `personal_ibkr`. No IBKR login, password or token ever passes through the app.
//
//  Field names are the ones the quant session fixed (11-11). Values are read leniently: numbers may come as text, and
//  anything unreadable is simply missing.
//

import Foundation

// MARK: - Status

/// GET /ibkr/status: {available, state, since, last_sync, message}.
public nonisolated struct IBKRStatus: Codable, Equatable, Sendable {
    public var available: Bool?
    public var state: IBKRState
    /// When the gateway entered this state, and when it last synced the account (ISO 8601).
    public var since: String?
    public var last_sync: String?
    /// Why a login failed, or other detail from the Mac mini.
    public var message: String?

    public init(available: Bool? = true, state: IBKRState, since: String? = nil, last_sync: String? = nil,
                message: String? = nil) {
        self.available = available
        self.state = state
        self.since = since
        self.last_sync = last_sync
        self.message = message
    }

    private enum CodingKeys: String, CodingKey { case available, state, since, last_sync, message }

    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            state = .unknown("")
            return
        }
        available = c.lenientBool(.available)
        state = IBKRState(c.lenientString(.state) ?? "")
        since = c.lenientString(.since)
        last_sync = c.lenientString(.last_sync)
        message = c.lenientString(.message).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(available, forKey: .available)
        try c.encode(state.rawValue, forKey: .state)
        try c.encodeIfPresent(since, forKey: .since)
        try c.encodeIfPresent(last_sync, forKey: .last_sync)
        try c.encodeIfPresent(message, forKey: .message)
    }
}

public nonisolated enum IBKRState: Equatable, Hashable, Sendable {
    /// Logged in, live data flowing.
    case connected
    /// The weekly re-authorization is due, or the session expired: the user has to log in again.
    case needsReauth
    /// The Mac mini is logging in.
    case loggingIn
    /// The login was started; waiting for the user to confirm in IBKR Mobile.
    case awaiting2FA
    /// The gateway is down (not a login problem).
    case offline
    /// Not set up on the Mac mini yet.
    case notConfigured
    case unknown(String)

    public init(_ raw: String) {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "connected": self = .connected
        case "needs_reauth": self = .needsReauth
        case "logging_in": self = .loggingIn
        case "awaiting_2fa": self = .awaiting2FA
        case "offline": self = .offline
        case "not_configured": self = .notConfigured
        default: self = .unknown(raw)
        }
    }

    public var rawValue: String {
        switch self {
        case .connected: "connected"
        case .needsReauth: "needs_reauth"
        case .loggingIn: "logging_in"
        case .awaiting2FA: "awaiting_2fa"
        case .offline: "offline"
        case .notConfigured: "not_configured"
        case .unknown(let raw): raw
        }
    }

    /// The states the home page's banner is up for (and /ibkr/status is read every few seconds).
    public var showsBanner: Bool {
        switch self {
        case .needsReauth, .loggingIn, .awaiting2FA: true
        default: false
        }
    }

    public var title: String {
        switch self {
        case .connected: "已连接"
        case .needsReauth: "需要重新授权"
        case .loggingIn: "正在登录"
        case .awaiting2FA: "等待在 IBKR Mobile 上确认"
        case .offline: "网关掉线"
        case .notConfigured: "还没配置好"
        case .unknown: "状态未知"
        }
    }
}

// MARK: - Account

/// GET /account: only the `personal_ibkr` part is read here; the rest of the document is the quant account's.
public nonisolated struct IBKRAccountDocument: Decodable, Equatable, Sendable {
    public var available: Bool?
    public var personal_ibkr: PersonalIBKR?

    private enum CodingKeys: String, CodingKey { case available, personal_ibkr }

    public init(available: Bool? = nil, personal_ibkr: PersonalIBKR? = nil) {
        self.available = available
        self.personal_ibkr = personal_ibkr
    }

    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        available = c.lenientBool(.available)
        personal_ibkr = try? c.decodeIfPresent(PersonalIBKR.self, forKey: .personal_ibkr)
    }
}

/// The personal IBKR account (`personal_ibkr` in GET /account): net liquidation, cash, buying power and positions.
/// Field names as the quant session fixed them. `stale` or `source == "flex"` (the daily statement instead of the live
/// gateway) means the figures are not live.
public nonisolated struct PersonalIBKR: Codable, Equatable, Sendable {
    /// false: not connected yet; only `message` (e.g. "IBKR 尚未接入") is meaningful.
    public var available: Bool?
    public var message: String?
    /// Data time, sync heartbeat and the last change of any value (ISO 8601 UTC).
    public var as_of: String?
    public var heartbeat_at: String?
    public var changed_at: String?
    /// "realtime" or "flex".
    public var source: String?
    public var stale: Bool?
    /// Why the figures are stale, in Chinese (may be empty).
    public var stale_reason: String?
    /// Only the last 4 digits, like "****1234".
    public var account: String?
    /// Base currency, e.g. "USD".
    public var currency: String?
    public var netValue: Double?
    public var cash: Double?
    public var buyingPower: Double?
    public var positions: [IBKRPosition] = []

    private enum CodingKeys: String, CodingKey {
        case available, message, as_of, heartbeat_at, changed_at, source, stale, stale_reason, account, currency
        case net_liquidation, cash, buying_power, positions
    }

    public init(available: Bool? = true, as_of: String? = nil, source: String? = "realtime", stale: Bool? = false,
                stale_reason: String? = nil, account: String? = nil, currency: String? = "USD", netValue: Double? = nil,
                cash: Double? = nil, buyingPower: Double? = nil, positions: [IBKRPosition] = []) {
        self.available = available
        self.as_of = as_of
        self.source = source
        self.stale = stale
        self.stale_reason = stale_reason
        self.account = account
        self.currency = currency
        self.netValue = netValue
        self.cash = cash
        self.buyingPower = buyingPower
        self.positions = positions
    }

    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        available = c.lenientBool(.available)
        message = c.lenientString(.message).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        as_of = c.lenientString(.as_of)
        heartbeat_at = c.lenientString(.heartbeat_at)
        changed_at = c.lenientString(.changed_at)
        source = c.lenientString(.source)
        stale = c.lenientBool(.stale)
        stale_reason = c.lenientString(.stale_reason)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        account = c.lenientString(.account)
        currency = c.lenientString(.currency)
        netValue = c.lenientDouble(.net_liquidation)
        cash = c.lenientDouble(.cash)
        buyingPower = c.lenientDouble(.buying_power)
        positions = ((try? c.decodeIfPresent([Lossy<IBKRPosition>].self, forKey: .positions)) ?? [])
            .compactMap(\.value).filter { $0.symbol != nil }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(available, forKey: .available)
        try c.encodeIfPresent(message, forKey: .message)
        try c.encodeIfPresent(as_of, forKey: .as_of)
        try c.encodeIfPresent(heartbeat_at, forKey: .heartbeat_at)
        try c.encodeIfPresent(changed_at, forKey: .changed_at)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encodeIfPresent(stale, forKey: .stale)
        try c.encodeIfPresent(stale_reason, forKey: .stale_reason)
        try c.encodeIfPresent(account, forKey: .account)
        try c.encodeIfPresent(currency, forKey: .currency)
        try c.encodeIfPresent(netValue, forKey: .net_liquidation)
        try c.encodeIfPresent(cash, forKey: .cash)
        try c.encodeIfPresent(buyingPower, forKey: .buying_power)
        try c.encode(positions, forKey: .positions)
    }

    /// The account's last four digits ("****1234" → "1234"), for 「尾号 1234」.
    public var accountTail: String? {
        guard let account else { return nil }
        let digits = account.filter(\.isNumber)
        let tail = String((digits.isEmpty ? account : digits).suffix(4))
        return tail.isEmpty ? nil : tail
    }

    /// The figures are not live: the server says so, or they come from the daily statement (flex).
    public var isMarkedStale: Bool { stale == true || source?.lowercased() == "flex" }

    /// `as_of` in epoch milliseconds.
    public var asOfMs: Double? { as_of.flatMap(JournalTime.milliseconds) }

    /// Sum of the positions' unrealized P&L (in their own currencies, so only meaningful when they share one).
    public var unrealizedTotal: Double? {
        let values = positions.compactMap(\.unrealizedPnl)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    /// Sum of today's P&L where the positions give it.
    public var dailyTotal: Double? {
        let values = positions.compactMap(\.dailyPnl)
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}

public nonisolated struct IBKRPosition: Codable, Equatable, Sendable, Identifiable {
    public var symbol: String?
    public var conID: Int?
    /// STK / OPT / FUT / CASH …
    public var secType: String?
    public var quantity: Double?
    /// Average cost per unit (avg_cost).
    public var cost: Double?
    public var marketValue: Double?
    public var unrealizedPnl: Double?
    /// Today's P&L; nil when IBKR does not give it.
    public var dailyPnl: Double?
    public var currency: String?

    public var id: String { conID.map(String.init) ?? ((symbol ?? "") + "|" + (secType ?? "") + "|" + (currency ?? "")) }

    private enum CodingKeys: String, CodingKey {
        case symbol, con_id, sec_type, quantity, avg_cost, market_value, unrealized_pnl, daily_pnl, currency
    }

    public init(symbol: String?, conID: Int? = nil, secType: String? = "STK", quantity: Double? = nil, cost: Double? = nil,
                marketValue: Double? = nil, unrealizedPnl: Double? = nil, dailyPnl: Double? = nil, currency: String? = nil) {
        self.symbol = symbol
        self.conID = conID
        self.secType = secType
        self.quantity = quantity
        self.cost = cost
        self.marketValue = marketValue
        self.unrealizedPnl = unrealizedPnl
        self.dailyPnl = dailyPnl
        self.currency = currency
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = c.lenientString(.symbol).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        conID = c.lenientDouble(.con_id).flatMap { abs($0) < 1e15 ? Int($0) : nil }
        secType = c.lenientString(.sec_type)
        quantity = c.lenientDouble(.quantity)
        cost = c.lenientDouble(.avg_cost)
        marketValue = c.lenientDouble(.market_value)
        unrealizedPnl = c.lenientDouble(.unrealized_pnl)
        dailyPnl = c.lenientDouble(.daily_pnl)
        currency = c.lenientString(.currency)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(symbol, forKey: .symbol)
        try c.encodeIfPresent(conID, forKey: .con_id)
        try c.encodeIfPresent(secType, forKey: .sec_type)
        try c.encodeIfPresent(quantity, forKey: .quantity)
        try c.encodeIfPresent(cost, forKey: .avg_cost)
        try c.encodeIfPresent(marketValue, forKey: .market_value)
        try c.encodeIfPresent(unrealizedPnl, forKey: .unrealized_pnl)
        try c.encodeIfPresent(dailyPnl, forKey: .daily_pnl)
        try c.encodeIfPresent(currency, forKey: .currency)
    }
}

// MARK: - Lenient keys

/// A coding key built from any name, for documents whose field names are not settled yet.
nonisolated struct FlexibleKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ name: String) { stringValue = name }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension KeyedDecodingContainer where Key == FlexibleKey {
    /// The first of `names` that holds a readable value.
    nonisolated func string(_ names: String...) -> String? {
        for name in names {
            if let value = lenientString(FlexibleKey(name)), !value.trimmingCharacters(in: .whitespaces).isEmpty { return value }
        }
        return nil
    }

    nonisolated func double(_ names: String...) -> Double? {
        for name in names { if let value = lenientDouble(FlexibleKey(name)) { return value } }
        return nil
    }

    nonisolated func bool(_ names: String...) -> Bool? {
        for name in names { if let value = lenientBool(FlexibleKey(name)) { return value } }
        return nil
    }
}
