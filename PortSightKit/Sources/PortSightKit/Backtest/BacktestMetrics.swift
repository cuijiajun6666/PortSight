//
//  BacktestMetrics.swift
//  PortSight
//
//  The 指标面板 figures, computed from the exported equity curve and trades (§二.5): Sharpe with a 90% interval,
//  annual return, max drawdown, win rate, average hold, yearly turnover, fees against gross profit, and the
//  same per calendar year. Plus the trade list's quick filters (§二.6). The equity curve may be daily or weekly
//  (C ti7 and the lockbox exams are weekly); Sharpe is annualised by the curve's own spacing.
//

import Foundation

public struct BacktestMetrics {
    public struct Period: Identifiable, Hashable {
        public let title: String
        public let annualReturn: Double
        public let sharpe: Double
        public let sharpeLow: Double
        public let sharpeHigh: Double
        public let maxDrawdown: Double
        public let winRate: Double
        public let trades: Int
        public let averageHoldHours: Double
        public let annualTurnover: Double
        public let feeShare: Double?
        public var id: String { title }
    }

    public let overall: Period
    public let byYear: [Period]
    /// Typical spacing of the equity curve in days (1 for a daily curve, 7 for a weekly one).
    public let stepDays: Double

    public init(trades: [BacktestTrade], equity: [BacktestEquityPoint]) {
        let step = Self.stepDays(Self.dailyNav(equity))
        stepDays = step
        overall = Self.period("全部", trades: trades, equity: equity, stepDays: step)
        let calendar = Self.utc
        let years = Set(equity.map { calendar.component(.year, from: $0.date) }).sorted()
        byYear = years.map { year in
            Self.period("\(year)",
                        trades: trades.filter { calendar.component(.year, from: $0.exitDate) == year },
                        equity: equity.filter { calendar.component(.year, from: $0.date) == year },
                        stepDays: step)
        }
    }

    /// 日 / 周 / every n days, for the explanation under the figures.
    public var samplingTitle: String {
        if stepDays <= 1.5 { return "日" }
        if abs(stepDays - 7) <= 1 { return "周" }
        return String(format: "每 %.0f 天", stepDays)
    }

    /// Median spacing between equity points, in days.
    static func stepDays(_ daily: [BacktestEquityPoint]) -> Double {
        let gaps = zip(daily.dropFirst(), daily).map { ($0.t - $1.t) / 86_400_000 }.filter { $0 > 0 }.sorted()
        return gaps.isEmpty ? 1 : max(1, gaps[gaps.count / 2])
    }

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func period(_ title: String, trades: [BacktestTrade], equity: [BacktestEquityPoint], stepDays: Double = 1) -> Period {
        let daily = dailyNav(equity)
        let returns = zip(daily.dropFirst(), daily).map { $0.nav / $1.nav - 1 }
        let days = max(1, (daily.last?.t ?? 0) - (daily.first?.t ?? 0)) / 86_400_000
        let years = max(days / 365, 1.0 / 365)
        let growth = (daily.last?.nav ?? 1) / (daily.first?.nav ?? 1)
        let annualReturn = pow(max(growth, 0.000_001), 1 / years) - 1

        // Sharpe on the curve's returns (daily, or weekly), annualised with √(365 / step days): crypto trades every
        // day. The interval uses the Lo (2002) standard error of a Sharpe ratio estimated from n i.i.d. returns.
        let n = Double(returns.count)
        let mean = n > 0 ? returns.reduce(0, +) / n : 0
        let variance = n > 1 ? returns.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / (n - 1) : 0
        let dailySharpe = variance > 0 ? mean / variance.squareRoot() : 0
        let standardError = n > 1 ? ((1 + dailySharpe * dailySharpe / 2) / n).squareRoot() : 0
        let scale = (365.0 / max(stepDays, 1)).squareRoot()

        var peak = 0.0, maxDrawdown = 0.0
        for point in daily {
            peak = max(peak, point.nav)
            if peak > 0 { maxDrawdown = min(maxDrawdown, point.nav / peak - 1) }
        }

        let wins = trades.filter(\.isWin).count
        let turnover = trades.map(Self.turnover).reduce(0, +)
        // Only trades that report both parts (some exports leave pnl_gross or fee out).
        let priced = trades.filter { $0.reportedPnlGross != nil && $0.reportedFee != nil }
        let gross = priced.map(\.pnlGross).filter { $0 > 0 }.reduce(0, +)
        let fees = priced.map(\.fee).reduce(0, +)

        return Period(title: title, annualReturn: annualReturn,
                      sharpe: dailySharpe * scale,
                      sharpeLow: (dailySharpe - 1.645 * standardError) * scale,
                      sharpeHigh: (dailySharpe + 1.645 * standardError) * scale,
                      maxDrawdown: maxDrawdown,
                      winRate: trades.isEmpty ? 0 : Double(wins) / Double(trades.count),
                      trades: trades.count,
                      averageHoldHours: trades.isEmpty ? 0 : trades.map(Self.holdHours).reduce(0, +) / Double(trades.count),
                      annualTurnover: turnover / years,
                      feeShare: gross > 0 ? fees / gross : nil)
    }

    /// hold_h, or the time from entry to exit when the export has none.
    static func holdHours(_ trade: BacktestTrade) -> Double {
        trade.holdH > 0 ? trade.holdH : max(0, trade.exitT - trade.entryT) / 3_600_000
    }

    /// Last NAV of each UTC day.
    static func dailyNav(_ equity: [BacktestEquityPoint]) -> [BacktestEquityPoint] {
        var byDay: [Int: BacktestEquityPoint] = [:]
        for point in equity { byDay[Int(point.t / 86_400_000)] = point }
        return byDay.keys.sorted().compactMap { byDay[$0] }
    }

    /// Sum of |Δweight| over the trade, including the final close to zero.
    public static func turnover(_ trade: BacktestTrade) -> Double {
        var previous = 0.0, total = 0.0
        for step in trade.sizePath {
            total += abs(step.w - previous)
            previous = step.w
        }
        return total + abs(previous)
    }
}

// MARK: - Trade list quick filters

public enum BacktestQuickFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case worstLosses = "亏损最大 20 笔"
    case shortHolds = "持有不到 1 小时"
    case reopened = "平了又开"

    public var id: String { rawValue }

    public func apply(_ trades: [BacktestTrade]) -> [BacktestTrade] {
        switch self {
        case .all:
            return trades
        case .worstLosses:
            return Array(trades.filter { $0.pnlNet < 0 }.sorted { $0.pnlNet < $1.pnlNet }.prefix(20))
        case .shortHolds:
            return trades.filter { $0.holdH < 1 }
        case .reopened:
            let ids = Self.reopenedIDs(trades)
            return trades.filter { ids.contains($0.id) }
        }
    }

    /// Trades opened within an hour after a trade on the same symbol and side was closed.
    public static func reopenedIDs(_ trades: [BacktestTrade]) -> Set<String> {
        var ids = Set<String>()
        for (_, group) in Dictionary(grouping: trades, by: { $0.symbol + $0.side.rawValue }) {
            let sorted = group.sorted { $0.entryT < $1.entryT }
            for (previous, next) in zip(sorted, sorted.dropFirst()) where next.entryT >= previous.exitT
                && next.entryT - previous.exitT <= 3_600_000 {
                ids.insert(next.id)
            }
        }
        return ids
    }
}
