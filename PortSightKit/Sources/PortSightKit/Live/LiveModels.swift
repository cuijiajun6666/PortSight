//
//  LiveModels.swift
//  PortSightKit
//
//  What the quant system reports about accounts that are trading now (Docs/live_feed_format.md): accounts,
//  open positions, working orders, fills, model status, closed trades and 1-minute bars. Times are UTC
//  milliseconds; JSON keys are snake_case. The app only reads these: it never places, cancels or edits an order.
//
//  Forward seal: the shadow ledger (影子账本: v3.0 主线 and challengers) exposes status, signal counts and
//  checks only. `LiveSnapshot.sealed()` drops anything else for it, even if a feed ever sent it.
//

import Foundation

nonisolated public enum LiveAccountKind: String, Codable, CaseIterable, Identifiable {
    case paper, live, shadow
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .paper: "模拟盘"
        case .live: "实盘"
        case .shadow: "影子账本"
        }
    }
    /// Paper and live accounts are the user's money and show everything; the shadow ledger is sealed.
    public var showsMoney: Bool { self != .shadow }
}

nonisolated public struct LiveAccount: Codable, Hashable, Identifiable {
    public let id: String
    public let kind: LiveAccountKind
    public let name: String
    public let currency: String
    /// Wallet balance: deposits plus realized profit minus fees. nil for the shadow ledger.
    public var balance: Double?
    /// Balance plus unrealized profit.
    public var equity: Double?
    public var available: Double?
    public var marginUsed: Double?
    public var todayPnl: Double?
    public var unrealizedPnl: Double?
    public var todayFee: Double?
    public var updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case id, kind, name, currency, balance, equity, available, marginUsed = "margin_used"
        case todayPnl = "today_pnl", unrealizedPnl = "unrealized_pnl", todayFee = "today_fee", updatedAt = "updated_at"
    }

    public init(id: String, kind: LiveAccountKind, name: String, currency: String = "USDT", balance: Double?,
                equity: Double?, available: Double?, marginUsed: Double?, todayPnl: Double?, unrealizedPnl: Double?,
                todayFee: Double? = nil, updatedAt: Double) {
        self.id = id; self.kind = kind; self.name = name; self.currency = currency; self.balance = balance
        self.equity = equity; self.available = available; self.marginUsed = marginUsed; self.todayPnl = todayPnl
        self.unrealizedPnl = unrealizedPnl; self.todayFee = todayFee; self.updatedAt = updatedAt
    }

    /// The same account with every money figure removed when it is the shadow ledger.
    public func sealed() -> LiveAccount {
        guard !kind.showsMoney else { return self }
        var copy = self
        copy.balance = nil; copy.equity = nil; copy.available = nil; copy.marginUsed = nil
        copy.todayPnl = nil; copy.unrealizedPnl = nil; copy.todayFee = nil
        return copy
    }
}

nonisolated public struct LivePosition: Codable, Hashable, Identifiable {
    public let id: String
    public let accountId: String
    public let model: String
    public let contract: String
    /// "perpetual" (永续) or "spot".
    public let instrument: String
    public let side: BacktestSide
    /// Contracts held (1 张 = 1 coin).
    public var size: Double
    public var leverage: Double
    /// Average entry price.
    public var entryPx: Double
    public var markPx: Double
    public var liquidationPx: Double?
    public var unrealizedPnl: Double
    /// Unrealized profit as a share of the position's margin.
    public var unrealizedPct: Double
    public var margin: Double
    public var stopPx: Double?
    public var targetPx: Double?
    public let openedAt: Double
    /// The trade this position becomes once closed (BacktestTrade.id), also on every fill.
    public let tradeId: String
    /// Size over time as share of equity (negative for shorts), like BacktestTrade.size_path.
    public var sizePath: [BacktestSizeStep]
    public var stops: [BacktestLevel]
    public var targets: [BacktestLevel]
    /// Profit already realized by reductions, and fees paid, in the account currency.
    public var realizedPnl: Double
    public var fee: Double

    enum CodingKeys: String, CodingKey {
        case id, accountId = "account_id", model, contract, instrument, side, size, leverage, entryPx = "entry_px"
        case markPx = "mark_px", liquidationPx = "liquidation_px", unrealizedPnl = "unrealized_pnl"
        case unrealizedPct = "unrealized_pct", margin, stopPx = "stop_px", targetPx = "target_px"
        case openedAt = "opened_at", tradeId = "trade_id", sizePath = "size_path", stops, targets
        case realizedPnl = "realized_pnl", fee
    }

    public init(id: String, accountId: String, model: String, contract: String, instrument: String = "perpetual",
                side: BacktestSide, size: Double, leverage: Double, entryPx: Double, markPx: Double,
                stopPx: Double?, targetPx: Double?, openedAt: Double, tradeId: String,
                sizePath: [BacktestSizeStep] = [], stops: [BacktestLevel] = [], targets: [BacktestLevel] = [],
                realizedPnl: Double = 0, fee: Double = 0) {
        self.id = id; self.accountId = accountId; self.model = model; self.contract = contract
        self.instrument = instrument; self.side = side; self.size = size; self.leverage = leverage
        self.entryPx = entryPx; self.markPx = markPx; self.stopPx = stopPx; self.targetPx = targetPx
        self.openedAt = openedAt; self.tradeId = tradeId; self.sizePath = sizePath; self.stops = stops
        self.targets = targets; self.realizedPnl = realizedPnl; self.fee = fee
        unrealizedPnl = 0; unrealizedPct = 0; margin = 0; liquidationPx = nil
        revalue(mark: markPx)
    }

    public var contractTitle: String { LiveFormat.contractTitle(contract, instrument: instrument) }
    public var notional: Double { size * markPx }

    /// Recomputes unrealized profit, margin and liquidation price at a new mark price.
    public mutating func revalue(mark: Double) {
        markPx = mark
        unrealizedPnl = side.sign * (mark - entryPx) * size
        margin = entryPx * size / max(leverage, 1)
        unrealizedPct = margin > 0 ? unrealizedPnl / margin : 0
        // Isolated-margin estimate with 0.5% maintenance margin.
        liquidationPx = leverage > 1 ? entryPx * (1 - side.sign * (1 / leverage - 0.005)) : nil
    }

    /// The position as a trade that exits now at the mark price, for the chart box and the detail card.
    public func chartTrade(now: Double, equity: Double) -> BacktestTrade {
        let nav = max(equity, 1)
        return BacktestTrade(
            id: tradeId, symbol: contract, side: side, entryT: openedAt, entryPx: entryPx, exitT: max(now, openedAt + 1),
            exitPx: markPx, exitReason: "open", sizePath: sizePath, stops: stops, targets: targets,
            pnlGross: (unrealizedPnl + realizedPnl) / nav, fee: fee / nav, funding: 0,
            pnlNet: (unrealizedPnl + realizedPnl - fee) / nav, mfe: 0, mae: 0, holdH: (now - openedAt) / 3_600_000,
            signalsAtEntry: [:])
    }
}

nonisolated public enum LiveOrderType: String, Codable {
    case market, limit, stop, takeProfit = "take_profit"
    public var title: String {
        switch self {
        case .market: "市价"
        case .limit: "限价"
        case .stop: "止损"
        case .takeProfit: "止盈"
        }
    }
}

nonisolated public enum LiveOrderSide: String, Codable {
    case buy, sell
    public var title: String { self == .buy ? "买入" : "卖出" }
}

nonisolated public enum LiveOrderStatus: String, Codable {
    case new, partiallyFilled = "partially_filled", filled, canceled, rejected
    public var title: String {
        switch self {
        case .new: "等待成交"
        case .partiallyFilled: "部分成交"
        case .filled: "已成交"
        case .canceled: "已撤销"
        case .rejected: "已拒绝"
        }
    }
    public var isOpen: Bool { self == .new || self == .partiallyFilled }
}

nonisolated public struct LiveOrder: Codable, Hashable, Identifiable {
    public let id: String
    public let accountId: String
    public let model: String
    public let contract: String
    public let type: LiveOrderType
    public let side: LiveOrderSide
    /// Which position the order opens or reduces.
    public let positionSide: BacktestSide
    public let reduceOnly: Bool
    /// Limit or trigger price; nil for market orders.
    public var price: Double?
    public var size: Double
    public var filled: Double
    public var status: LiveOrderStatus
    public let createdAt: Double
    public var updatedAt: Double
    public var tradeId: String?

    enum CodingKeys: String, CodingKey {
        case id, accountId = "account_id", model, contract, type, side, positionSide = "position_side"
        case reduceOnly = "reduce_only", price, size, filled, status, createdAt = "created_at"
        case updatedAt = "updated_at", tradeId = "trade_id"
    }

    public init(id: String, accountId: String, model: String, contract: String, type: LiveOrderType,
                side: LiveOrderSide, positionSide: BacktestSide, reduceOnly: Bool, price: Double?, size: Double,
                filled: Double = 0, status: LiveOrderStatus = .new, createdAt: Double, updatedAt: Double? = nil,
                tradeId: String? = nil) {
        self.id = id; self.accountId = accountId; self.model = model; self.contract = contract; self.type = type
        self.side = side; self.positionSide = positionSide; self.reduceOnly = reduceOnly; self.price = price
        self.size = size; self.filled = filled; self.status = status; self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt; self.tradeId = tradeId
    }

    /// 开多 / 平空 … from the side and whether it only reduces.
    public var actionTitle: String { (reduceOnly ? "平" : "开") + positionSide.title }
}

nonisolated public enum LiveAction: String, Codable {
    case open, add, reduce, close
    public var title: String {
        switch self {
        case .open: "开"
        case .add: "加"
        case .reduce: "减"
        case .close: "平"
        }
    }
}

nonisolated public struct LiveFill: Codable, Hashable, Identifiable {
    public let id: String
    public let accountId: String
    public let model: String
    public let orderId: String
    public let tradeId: String
    public let t: Double
    public let contract: String
    public let side: LiveOrderSide
    public let positionSide: BacktestSide
    public let action: LiveAction
    public let price: Double
    public let size: Double
    public let fee: Double
    /// Profit realized by this fill (0 for opens and adds), before its fee.
    public let realizedPnl: Double
    /// signal / add / reduce / partial_tp / take_profit / stop_loss / signal_exit / signal_reverse / time_exit …
    public let reason: String

    enum CodingKeys: String, CodingKey {
        case id, accountId = "account_id", model, orderId = "order_id", tradeId = "trade_id", t, contract, side
        case positionSide = "position_side", action, price, size, fee, realizedPnl = "realized_pnl", reason
    }

    public init(id: String, accountId: String, model: String, orderId: String, tradeId: String, t: Double,
                contract: String, side: LiveOrderSide, positionSide: BacktestSide, action: LiveAction, price: Double,
                size: Double, fee: Double, realizedPnl: Double, reason: String) {
        self.id = id; self.accountId = accountId; self.model = model; self.orderId = orderId; self.tradeId = tradeId
        self.t = t; self.contract = contract; self.side = side; self.positionSide = positionSide
        self.action = action; self.price = price; self.size = size; self.fee = fee; self.realizedPnl = realizedPnl
        self.reason = reason
    }

    /// 开多 / 加空 / 减多 / 平空.
    public var actionTitle: String { action.title + positionSide.title }

    public var reasonTitle: String {
        switch reason {
        case "signal": "信号"
        case "add": "加仓"
        case "reduce": "减仓"
        default: BacktestExitReason.title(reason)
        }
    }

    /// "v4 G263 开多 BTCUSDT 0.12 张 @ 68,420.5"
    public var headline: String {
        "\(model) \(actionTitle) \(contract) \(LiveFormat.size(size)) 张 @ \(LiveFormat.price(price))"
    }

    /// Realized profit after this fill's fee.
    public var netPnl: Double { realizedPnl - fee }
}

nonisolated public enum LiveModelState: String, Codable {
    case running, paused, error
    public var title: String {
        switch self {
        case .running: "运行中"
        case .paused: "暂停"
        case .error: "出错"
        }
    }
}

nonisolated public struct LiveCheck: Codable, Hashable, Identifiable {
    public let name: String
    public let pass: Bool
    public let detail: String?

    public var id: String { name }

    public init(name: String, pass: Bool, detail: String? = nil) { self.name = name; self.pass = pass; self.detail = detail }

    public var title: String { pass ? "过" : "不过" }
}

nonisolated public struct LiveModelStatus: Codable, Hashable, Identifiable {
    public let accountId: String
    public let model: String
    public var state: LiveModelState
    public var lastRun: Double?
    public var nextRun: Double?
    /// Latest signal values (mu_4h, entry_thr, …).
    public var signals: [String: Double]
    public var checks: [LiveCheck]
    public var signalsToday: Int
    public var signalsTotal: Int
    /// Contracts the model may trade.
    public var contracts: [String]
    public var message: String?

    public var id: String { accountId + "/" + model }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id", model, state, lastRun = "last_run", nextRun = "next_run", signals, checks
        case signalsToday = "signals_today", signalsTotal = "signals_total", contracts, message
    }

    public init(accountId: String, model: String, state: LiveModelState, lastRun: Double?, nextRun: Double?,
                signals: [String: Double], checks: [LiveCheck], signalsToday: Int, signalsTotal: Int,
                contracts: [String], message: String? = nil) {
        self.accountId = accountId; self.model = model; self.state = state; self.lastRun = lastRun
        self.nextRun = nextRun; self.signals = signals; self.checks = checks; self.signalsToday = signalsToday
        self.signalsTotal = signalsTotal; self.contracts = contracts; self.message = message
    }

    public var passedChecks: Int { checks.filter(\.pass).count }
}

/// A closed trade of a paper or live account, in the backtest trade format so the same chart draws it.
nonisolated public struct LiveTradeRecord: Codable, Hashable, Identifiable {
    public let accountId: String
    public let model: String
    public let trade: BacktestTrade
    /// Realized profit and fees in the account currency.
    public let realizedPnl: Double
    public let fee: Double

    public var id: String { trade.id }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id", model, trade, realizedPnl = "realized_pnl", fee
    }

    public init(accountId: String, model: String, trade: BacktestTrade, realizedPnl: Double, fee: Double) {
        self.accountId = accountId; self.model = model; self.trade = trade; self.realizedPnl = realizedPnl; self.fee = fee
    }
}

/// Everything about the accounts at one moment; sent on connect and whenever the app asks again.
nonisolated public struct LiveSnapshot: Codable {
    public let t: Double
    public var accounts: [LiveAccount]
    public var positions: [LivePosition]
    /// Working orders only (new / partially filled).
    public var orders: [LiveOrder]
    public var models: [LiveModelStatus]
    /// Recent history, newest last; optional.
    public var fills: [LiveFill]
    public var closedTrades: [LiveTradeRecord]

    enum CodingKeys: String, CodingKey {
        case t, accounts, positions, orders, models, fills, closedTrades = "closed_trades"
    }

    public init(t: Double, accounts: [LiveAccount], positions: [LivePosition], orders: [LiveOrder],
                models: [LiveModelStatus], fills: [LiveFill] = [], closedTrades: [LiveTradeRecord] = []) {
        self.t = t; self.accounts = accounts; self.positions = positions; self.orders = orders; self.models = models
        self.fills = fills; self.closedTrades = closedTrades
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decode(Double.self, forKey: .t)
        accounts = try c.decode([LiveAccount].self, forKey: .accounts)
        positions = try c.decodeIfPresent([LivePosition].self, forKey: .positions) ?? []
        orders = try c.decodeIfPresent([LiveOrder].self, forKey: .orders) ?? []
        models = try c.decodeIfPresent([LiveModelStatus].self, forKey: .models) ?? []
        fills = try c.decodeIfPresent([LiveFill].self, forKey: .fills) ?? []
        closedTrades = try c.decodeIfPresent([LiveTradeRecord].self, forKey: .closedTrades) ?? []
    }

    /// Applies the shadow-ledger seal: its accounts lose every money figure and its positions, orders, fills and
    /// trades are dropped. Model status (state, signal counts, checks) stays.
    public func sealed() -> LiveSnapshot {
        let shadow = Set(accounts.filter { !$0.kind.showsMoney }.map(\.id))
        var copy = self
        copy.accounts = accounts.map { $0.sealed() }
        copy.positions = positions.filter { !shadow.contains($0.accountId) }
        copy.orders = orders.filter { !shadow.contains($0.accountId) }
        copy.fills = fills.filter { !shadow.contains($0.accountId) }
        copy.closedTrades = closedTrades.filter { !shadow.contains($0.accountId) }
        return copy
    }
}

nonisolated public enum LiveEventType: String, Codable {
    case fill, order, position, positionClosed = "position_closed", model, bar
}

/// One entry of the append-only event stream. `seq` only ever grows; the app ignores what it has already seen.
nonisolated public struct LiveEvent: Codable, Hashable, Identifiable {
    public let seq: Int
    public let t: Double
    public let type: LiveEventType
    public let accountId: String
    public var fill: LiveFill?
    public var order: LiveOrder?
    public var position: LivePosition?
    /// For position_closed: the closed position's id.
    public var positionId: String?
    public var model: LiveModelStatus?
    /// For bar: a 1-minute bar update.
    public var bar: LiveBarUpdate?

    public var id: Int { seq }

    enum CodingKeys: String, CodingKey {
        case seq, t, type, accountId = "account_id", fill, order, position, positionId = "position_id", model, bar
    }

    public init(seq: Int, t: Double, type: LiveEventType, accountId: String, fill: LiveFill? = nil,
                order: LiveOrder? = nil, position: LivePosition? = nil, positionId: String? = nil,
                model: LiveModelStatus? = nil, bar: LiveBarUpdate? = nil) {
        self.seq = seq; self.t = t; self.type = type; self.accountId = accountId; self.fill = fill
        self.order = order; self.position = position; self.positionId = positionId; self.model = model; self.bar = bar
    }

    /// One line for a banner when the model acts.
    public var headline: String? {
        if let fill { return fill.headline }
        if let order, type == .order {
            let price = order.price.map { " @ " + LiveFormat.price($0) } ?? ""
            return "\(order.model) \(order.type.title)委托 \(order.actionTitle) \(order.contract) \(LiveFormat.size(order.size)) 张\(price) · \(order.status.title)"
        }
        return nil
    }
}

/// One 1-minute bar (or an update of the bar still forming).
nonisolated public struct LiveBarUpdate: Codable, Hashable {
    public let contract: String
    /// Always "1m" from the feed; the app builds 5m / 15m / 1h itself.
    public let timeframe: BacktestTimeframe
    public let bar: BacktestBar
    /// false while the minute is still forming.
    public let closed: Bool

    public init(contract: String, timeframe: BacktestTimeframe = .m1, bar: BacktestBar, closed: Bool) {
        self.contract = contract; self.timeframe = timeframe; self.bar = bar; self.closed = closed
    }
}

/// Text for the 实时 pages: local times, grouped prices, sizes and signed money.
nonisolated public enum LiveFormat {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    public static func time(_ milliseconds: Double) -> String { timeFormatter.string(from: Date(milliseconds: milliseconds)) }
    public static func clock(_ milliseconds: Double) -> String { clockFormatter.string(from: Date(milliseconds: milliseconds)) }

    public static func price(_ value: Double) -> String {
        let digits = value >= 1_000 ? 1 : value >= 10 ? 2 : 4
        return value.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "en_US")))
    }

    public static func size(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)).locale(Locale(identifier: "en_US")))
    }

    public static func money(_ value: Double, digits: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "en_US")))
    }

    public static func signedMoney(_ value: Double, digits: Int = 2) -> String {
        (value >= 0 ? "+" : "−") + money(abs(value), digits: digits)
    }

    public static func contractTitle(_ contract: String, instrument: String = "perpetual") -> String {
        instrument == "perpetual" ? contract + " 永续" : contract
    }
}
