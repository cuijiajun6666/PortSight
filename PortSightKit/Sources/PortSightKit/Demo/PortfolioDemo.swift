import Foundation
import Combine

@MainActor public final class PortfolioDemo: ObservableObject {
    @Published public var scope: PortfolioScope = .all
    @Published public var showNotifications = false
    @Published public var showSettings = false
    /// 已确认 / 已读 notices, kept on this device across launches (never sent to the relay).
    @Published public var acknowledged: Set<String> = StoredIDs.load(StoredIDs.acknowledgedKey) {
        didSet { StoredIDs.save(acknowledged, StoredIDs.acknowledgedKey) }
    }
    @Published public var read: Set<String> = StoredIDs.load(StoredIDs.noticesReadKey) {
        didSet { StoredIDs.save(read, StoredIDs.noticesReadKey) }
    }
    @Published public var watchlist = ["NVDA", "AAPL", "MSFT"]
    // Every figure below is the built-in portfolio before pairing, and real data after (LivePortfolio): the
    // personal IBKR account; the quant account, history, activity and orders are empty until the relay has them.
    // Pages use these (or the per-scope functions further down), never DemoPortfolioData directly.

    /// Real data instead of the built-in portfolio.
    public var isLive: Bool { Portfolio.isLive }
    /// What the page should say about missing or not-live real data for the current scope (nil: nothing).
    public var liveNote: String? { Portfolio.note(scope) }

    public var holdings: [DemoHolding] { combined(scope) }
    public var total: Double { total(scope) }
    public var cash: Double { cash(scope) }
    public var principal: Double { principal(scope) }
    public var pnl: Double { pnl(scope) }
    public var dayPnL: Double { dayPnL(scope) }

    public func lots(_ scope: PortfolioScope) -> [DemoHolding] { Portfolio.lots(scope) }
    public func combined(_ scope: PortfolioScope) -> [DemoHolding] { Portfolio.combined(scope) }
    public func cash(_ scope: PortfolioScope) -> Double { Portfolio.cash(scope) }
    public func total(_ scope: PortfolioScope) -> Double { Portfolio.total(scope) }
    public func pnl(_ scope: PortfolioScope) -> Double { Portfolio.pnl(scope) }
    public func principal(_ scope: PortfolioScope) -> Double { Portfolio.principal(scope) }
    public func dayPnL(_ scope: PortfolioScope) -> Double { Portfolio.dayPnL(scope) }
    public func points(_ scope: PortfolioScope, range: IBKREquityRange = .standard) -> [DemoPoint] {
        Portfolio.points(scope, range: range)
    }
    public func hasFigures(_ scope: PortfolioScope) -> Bool { Portfolio.hasFigures(scope) }

    public var notices: [DemoNotice] {
        (RelayNotices.current() ?? DemoPortfolioData.notices).filter { scope == .all || $0.owner == scope || $0.owner == .all }
    }
    /// Notices still waiting for 确认已查看 (requires_ack from the relay; critical built-in ones), not expired.
    /// Notices still waiting for 确认已查看. An 「IBKR 需要重新授权」 notice (link ibkr:reauth) stops waiting once IBKR is
    /// connected again: the re-authorization it asked for is done (it stays in the message centre).
    public var pendingCritical: [DemoNotice] {
        let reauthorized = IBKRStore.shared.state == .connected
        return notices.filter {
            $0.needsAcknowledgement() && !acknowledged.contains($0.id) && !(reauthorized && $0.link == "ibkr:reauth")
        }
    }
    /// Built-in activity before pairing; none once live (the relay's activity feed is not there yet).
    public var activities: [DemoActivity] { Portfolio.activities(scope) }

    /// Built-in orders before pairing; once live the personal IBKR account's orders (latest status of each).
    public var orders: [PortfolioOrder] { Portfolio.orders(scope) }
    public var snapshots: [AssetChartSnapshot] { points(scope).map { AssetChartSnapshot(date: $0.date, value: $0.equity) } }
    public var positions: [Position] { holdings.filter { $0.kind != "加密货币" }.map { holding in
        Position(symbol: "US." + holding.symbol, name: holding.name, quantity: holding.quantity, avgCost: holding.cost,
                 marketValue: holding.value, pnl: holding.pnl, pnlPercent: holding.pnl / (holding.cost * holding.quantity) * 100,
                 realizedPnL: 0, unrealizedPnL: holding.pnl, isEtf: holding.kind == "ETF", assetClass: holding.kind)
    } }
    public var crypto: [PortfolioAsset] { holdings.filter { $0.kind == "加密货币" }.map(\.asset) }

    /// Today's P&L as a fraction of yesterday's close (total minus today's move).
    public var dayFraction: Double { dayPnL / max(1, total - dayPnL) }
    /// Cumulative P&L as a fraction of principal.
    public var pnlFraction: Double { pnl / max(1, principal) }

    /// Today's best and worst holding by percentage move: one entry when only one holding moved (labelled by its
    /// direction), none when nothing did.
    public var bestAndWorst: [(label: String, holding: DemoHolding)] {
        let moved = holdings.filter { $0.previous > 0 && $0.price != $0.previous }
        guard let best = moved.max(by: { $0.dayChange < $1.dayChange }),
              let worst = moved.min(by: { $0.dayChange < $1.dayChange }) else { return [] }
        if best.id == worst.id { return [(best.dayChange > 0 ? "今日最佳" : "今日最差", best)] }
        return [("今日最佳", best), ("今日最差", worst)]
    }
    public func apply(to model: AssetViewModel) {
        model.totalAsset = total; model.principalTotal = principal; model.buyingPower = cash
        model.isConnected = false; model.connectionStatus = "已连接"; model.currency = "USD"
    }

    public init() {}
}
extension DemoHolding {
    /// Today's move as a fraction of the previous close (0 when there is no previous close).
    public var dayChange: Double { previous > 0 ? price / previous - 1 : 0 }

    public var asset: PortfolioAsset {
        PortfolioAsset(type: kind == "加密货币" ? .crypto : .stock, symbol: symbol, name: name, quantity: quantity,
                       avgCost: cost, currentPrice: price, prevClosePrice: previous, marketValue: value, realizedPnL: 0,
                       unrealizedPnL: pnl, pnlRatio: pnl / (cost * quantity) * 100, currency: "USD", source: "demo")
    }
}

/// Sets of ids kept in UserDefaults (notice and alert read / acknowledged state), at most `limit` each.
/// The portfolio the pages show: the built-in one before pairing, real data after (LivePortfolio: the personal IBKR
/// account; the quant account, history, activity and orders empty until the relay has them). PortfolioDemo's
/// figures and every Kit model that needs holdings read through here, never DemoPortfolioData directly.
public enum Portfolio {
    // Once paired, real data and the built-in portfolio are shown together, so every page looks complete: whatever the
    // relay has is real (the personal IBKR account's value, cash, P&L, positions, history, fills, orders and cash
    // movements); whatever it does not have is filled from the built-in portfolio (the quant account, kinds of holding
    // the account has none of — e.g. ETFs —, a few more stocks, prices, AI analysis…). Before pairing everything is
    // built in, as it always was.

    public static var isLive: Bool { LivePortfolio.isLive }

    /// A note for figures that are real but not live (「非实时 · 截至 …」); nil otherwise.
    public static func note(_ scope: PortfolioScope) -> String? { isLive ? LivePortfolio.note(scope) : nil }

    /// The IBKR account has been read (else the personal part is the built-in one too).
    static var hasAccount: Bool { LivePortfolio.account != nil }

    /// Lots of `scope` as held (one per owner and symbol).
    public static func lots(_ scope: PortfolioScope) -> [DemoHolding] {
        guard isLive, hasAccount else { return DemoPortfolioData.lots(scope) }
        switch scope {
        case .quant: return DemoPortfolioData.lots(.quant)
        case .personal: return personalLots
        case .all: return personalLots + DemoPortfolioData.lots(.quant)
        }
    }

    /// The real positions, then the built-in fillers (LivePortfolio.fillers).
    static var personalLots: [DemoHolding] {
        let real = LivePortfolio.holdings(LivePortfolio.account)
        return real + LivePortfolio.fillers(real: real)
    }

    /// Holdings of `scope`, one per symbol, largest first.
    public static func combined(_ scope: PortfolioScope) -> [DemoHolding] {
        guard isLive, hasAccount else { return DemoPortfolioData.combined(scope) }
        return Dictionary(grouping: lots(scope), by: \.symbol).values.map { group in
            let first = group[0], quantity = group.reduce(0) { $0 + $1.quantity }
            return DemoHolding(owner: scope, symbol: first.symbol, name: first.name, kind: first.kind, quantity: quantity,
                               cost: quantity == 0 ? first.cost : group.reduce(0) { $0 + $1.quantity * $1.cost } / quantity,
                               price: first.price, previous: first.previous)
        }.sorted { abs($0.value) > abs($1.value) }
    }

    /// Real for the personal account (IBKR), built in for the quant account; 全部 adds them up.
    public static func cash(_ scope: PortfolioScope) -> Double {
        figure(scope) { LivePortfolio.cash(.personal, account: $0) } builtIn: { DemoPortfolioData.cash($0) }
    }

    public static func total(_ scope: PortfolioScope) -> Double {
        figure(scope) { LivePortfolio.total(.personal, account: $0) } builtIn: { DemoPortfolioData.total($0) }
    }

    public static func pnl(_ scope: PortfolioScope) -> Double {
        figure(scope) { LivePortfolio.pnl(.personal, account: $0) } builtIn: { DemoPortfolioData.pnl($0) }
    }

    public static func principal(_ scope: PortfolioScope) -> Double {
        figure(scope) { LivePortfolio.total(.personal, account: $0) - LivePortfolio.pnl(.personal, account: $0) }
            builtIn: { DemoPortfolioData.principal($0) }
    }

    public static func dayPnL(_ scope: PortfolioScope) -> Double {
        figure(scope) { LivePortfolio.dayPnL(.personal, account: $0) } builtIn: { DemoPortfolioData.dayPnL($0) }
    }

    /// The personal part from the IBKR account when it has been read, the quant part built in.
    private static func figure(_ scope: PortfolioScope, real: (PersonalIBKR) -> Double,
                               builtIn: (PortfolioScope) -> Double) -> Double {
        guard isLive, let account = LivePortfolio.account else { return builtIn(scope) }
        switch scope {
        case .personal: return real(account)
        case .quant: return builtIn(.quant)
        case .all: return real(account) + builtIn(.quant)
        }
    }

    /// The value history of `scope` over `range`: the personal account's real curve (GET /ibkr/equity) once it has
    /// been read, the built-in curve otherwise; the quant account's is built in, and 全部 is the personal curve plus
    /// the quant account's value.
    public static func points(_ scope: PortfolioScope, range: IBKREquityRange = .standard) -> [DemoPoint] {
        guard isLive, scope != .quant,
              let real = IBKREquityStore.shared.document(range)?.chartPoints, real.count >= 2 else {
            return DemoPortfolioData.points(scope)
        }
        guard scope == .all else { return real }
        let quant = DemoPortfolioData.total(.quant)
        var peak = 0.0
        return real.map { point in
            let value = point.equity + quant
            peak = max(peak, value)
            return DemoPoint(id: point.id, date: point.date, equity: value, benchmark: value,
                             drawdown: peak > 0 ? (peak - value) / peak : 0)
        }
    }

    /// The real curve is on screen for `scope` and `range` (else the built-in one).
    public static func hasRealHistory(_ scope: PortfolioScope, range: IBKREquityRange = .standard) -> Bool {
        isLive && scope != .quant && (IBKREquityStore.shared.document(range)?.chartPoints.count ?? 0) >= 2
    }

    /// Every scope has figures: real where the relay has them, built in elsewhere.
    public static func hasFigures(_ scope: PortfolioScope) -> Bool { true }

    /// Activity rows for `scope`: the built-in ones before pairing; once live the personal IBKR account's fills,
    /// orders, position changes and cash (IBKRActivityStore), with the built-in quant (and shared) rows; built-in
    /// personal rows too while the IBKR account has none.
    public static func activities(_ scope: PortfolioScope) -> [DemoActivity] {
        let builtIn = DemoPortfolioData.activities.filter { scope == .all || $0.owner == scope || $0.owner == .all }
        guard isLive else { return builtIn }
        let real = scope == .quant ? [] : IBKRActivityList.timeline(IBKRActivityStore.shared.items).map(\.asDemoActivity)
        let fillers = builtIn.filter { $0.owner != .personal || real.isEmpty }
        return real + fillers
    }

    /// Orders for `scope`: the built-in ones before pairing; once live the personal IBKR account's orders (latest
    /// status of each), with the built-in quant order; the built-in personal one too while IBKR has none.
    public static func orders(_ scope: PortfolioScope) -> [PortfolioOrder] {
        let builtIn = builtInOrders.filter { scope == .all || $0.0 == scope }
        guard isLive else { return builtIn.map(\.1) }
        let real = scope == .quant ? [] : IBKRActivityList.orders(IBKRActivityStore.shared.items).compactMap(\.asPortfolioOrder)
        return real + builtIn.filter { $0.0 != .personal || real.isEmpty }.map(\.1)
    }

    static var builtInOrders: [(PortfolioScope, PortfolioOrder)] {
        [
            (.quant, PortfolioOrder(id: "demo-nvda", symbol: "US.NVDA", side: .buy, status: .completed,
                price: 140, quantity: 10, date: DemoPortfolioData.date, orderStateText: "已成交")),
            (.personal, PortfolioOrder(id: "demo-aapl", symbol: "US.AAPL", side: .buy, status: .completed,
                price: 220, quantity: 5, date: DemoPortfolioData.date.addingTimeInterval(-86400), orderStateText: "已成交")),
        ]
    }

    /// Nothing is missing any more (built-in rows fill in): kept for the pages that ask.
    public static func activityNote(_ scope: PortfolioScope) -> String? { nil }

    /// The holding of `symbol` in all accounts, if held.
    public static func holding(_ symbol: String) -> DemoHolding? {
        let ticker = symbol.replacingOccurrences(of: "US.", with: "").uppercased()
        return combined(.all).first { $0.symbol.uppercased() == ticker }
    }
}

public enum StoredIDs {
    public static let acknowledgedKey = "notices.acknowledged"
    public static let noticesReadKey = "notices.read"
    public static let alertsReadKey = "alerts.read"
    static let limit = 3_000

    public static func load(_ key: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    public static func save(_ ids: Set<String>, _ key: String) {
        UserDefaults.standard.set(Array(ids.sorted().suffix(limit)), forKey: key)
    }
}
