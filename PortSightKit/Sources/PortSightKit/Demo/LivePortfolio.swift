//
//  LivePortfolio.swift
//  PortSightKit
//
//  The personal IBKR account once a relay is paired (IBKRStore, GET /account → personal_ibkr): net liquidation, cash,
//  positions and today's P&L, mapped to the holdings the pages draw. Portfolio shows them together with built-in
//  data for whatever the relay does not have (fillers below, the quant account), so every page looks complete.
//

import Foundation

public enum LivePortfolio {
    /// Real data instead of the built-in portfolio: a relay is paired and its data (not the sample) is on screen.
    public static var isLive: Bool { RelayNotices.usesRelay }

    /// The personal IBKR account as last read (also the copy kept for offline use).
    public static var account: PersonalIBKR? { IBKRStore.shared.account.document }

    // MARK: Holdings

    /// The personal account's positions as holdings, largest first. Cash balances (CASH) are left out: they are in
    /// `cash` already.
    public static func holdings(_ account: PersonalIBKR?) -> [DemoHolding] {
        (account?.positions ?? []).compactMap(holding).sorted { abs($0.value) > abs($1.value) }
    }

    static func holding(_ position: IBKRPosition) -> DemoHolding? {
        guard let symbol = position.symbol, let quantity = position.quantity, quantity != 0,
              position.secType?.uppercased() != "CASH" else { return nil }
        let value = position.marketValue ?? 0
        let price = value / quantity
        // Yesterday's close from today's P&L; without it the position simply did not move today.
        let previous = position.dailyPnl.map { (value - $0) / quantity } ?? price
        return DemoHolding(owner: .personal, symbol: symbol, name: symbol, kind: kind(position.secType, symbol: symbol),
                           quantity: quantity, cost: position.cost ?? price, price: price, previous: previous)
    }

    /// 股票 / ETF / 期权 / 期货 / 债券 / 基金 / 加密货币, from IBKR's sec_type (an ETF is a STK to IBKR: well-known
    /// funds are named as such).
    static func kind(_ secType: String?, symbol: String) -> String {
        switch secType?.uppercased() {
        case "OPT", "FOP": "期权"
        case "FUT": "期货"
        case "BOND": "债券"
        case "FUND", "MF": "基金"
        case "CRYPTO": "加密货币"
        default: knownFunds.contains(symbol.uppercased()) ? "ETF" : "股票"
        }
    }

    static let knownFunds: Set<String> = [
        "SPY", "QQQ", "VOO", "IVV", "VTI", "DIA", "IWM", "TLT", "IEF", "SHY", "BND", "AGG", "LQD", "HYG", "GLD", "SLV",
        "EFA", "EEM", "VEA", "VWO", "XLK", "XLF", "XLE", "XLV", "XLY", "XLP", "XLI", "XLU", "XLB", "XLRE", "SMH",
        "SOXX", "ARKK", "TQQQ", "SQQQ", "SCHD", "VIG", "VYM", "JEPI", "JEPQ", "VGT", "VUG", "IAU", "USO", "KWEB", "FXI",
    ]

    /// Lots for `scope`: the personal account's; the quant account has none yet.
    public static func lots(_ scope: PortfolioScope, account: PersonalIBKR?) -> [DemoHolding] {
        scope == .quant ? [] : holdings(account)
    }

    // MARK: Figures

    public static func cash(_ scope: PortfolioScope, account: PersonalIBKR?) -> Double {
        scope == .quant ? 0 : account?.cash ?? 0
    }

    /// Net liquidation as IBKR reports it (cash and positions in the base currency); without it, cash plus positions.
    public static func total(_ scope: PortfolioScope, account: PersonalIBKR?) -> Double {
        guard scope != .quant else { return 0 }
        if let net = account?.netValue { return net }
        return cash(scope, account: account) + lots(scope, account: account).reduce(0) { $0 + $1.value }
    }

    /// Unrealized P&L of the positions (IBKR's own figure where it gives one).
    public static func pnl(_ scope: PortfolioScope, account: PersonalIBKR?) -> Double {
        guard scope != .quant, let account else { return 0 }
        return account.positions.reduce(0) { sum, position in
            guard position.secType?.uppercased() != "CASH" else { return sum }
            return sum + (position.unrealizedPnl ?? 0)
        }
    }

    /// Today's P&L (daily_pnl; positions without it count as unchanged).
    public static func dayPnL(_ scope: PortfolioScope, account: PersonalIBKR?) -> Double {
        guard scope != .quant else { return 0 }
        return account?.dailyTotal ?? 0
    }

    // MARK: Built-in fillers

    /// Built-in holdings shown with the real ones once paired, so the personal page looks complete: the built-in
    /// personal stocks the account does not hold, built-in crypto when it holds none, and an ETF when it holds none.
    public static func fillers(real: [DemoHolding]) -> [DemoHolding] {
        let held = Set(real.map { $0.symbol.uppercased() })
        let kinds = Set(real.map(\.kind))
        var result = DemoPortfolioData.lots(.personal).filter { lot in
            guard !held.contains(lot.symbol.uppercased()) else { return false }
            return lot.kind == "股票" || !kinds.contains(lot.kind)
        }
        if !kinds.contains("ETF"), !held.contains(extraETF.symbol) { result.append(extraETF) }
        return result
    }

    static let extraETF = DemoHolding(owner: .personal, symbol: "VOO", name: "Vanguard S&P 500 ETF", kind: "ETF",
                                      quantity: 10, cost: 480, price: 520, previous: 517)

    // MARK: Notes

    /// 「非实时 · 截至 …」 while the IBKR figures are real but not live; nil otherwise (built-in figures fill in
    /// whatever is missing, so nothing else needs saying).
    public static func note(_ scope: PortfolioScope, store: IBKRStore = .shared) -> String? {
        guard scope != .quant, store.account.document != nil else { return nil }
        return store.delayedNote()
    }

    /// The personal IBKR account has been read.
    public static func hasFigures(_ scope: PortfolioScope) -> Bool {
        scope != .quant && account != nil
    }
}
