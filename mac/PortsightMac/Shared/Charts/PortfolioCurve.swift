import SwiftUI
import PortSightKit

/// One point of a portfolio's value curve as the Mac pages draw it.
struct PortfolioCurvePoint: Identifiable {
    let id: Int
    let date: Date
    /// The value in USD.
    let value: Double
    /// Growth since the curve's first point with deposits and withdrawals taken out (1 at the start): IBKR's
    /// time-weighted return (twr_cum) for 个人, the range's P&L over the starting value for 全部, the value itself
    /// for the built-in curve (which has no cash flows).
    let growth: Double
    /// The benchmark's growth since the first point (1 at the start).
    let benchmark: Double
    /// The benchmark in USD (the built-in benchmark; on the real curve it starts at the first value).
    let benchmarkValue: Double
    /// Fall from the highest growth so far, as a fraction.
    let drawdown: Double
}

/// The value curve of a scope over an IBKR range, for the dashboard, analysis, review and terminal charts: the real
/// IBKR curve (GET /ibkr/equity, through Portfolio.points) when that range has been read, else the built-in one.
/// Whatever the relay does not have is filled in from built-in data — the benchmark, the quant account's value in
/// 全部, and (once paired, on the built-in curve) a deposit marker — so every chart looks complete. Before pairing the
/// curve is the built-in one exactly as it always was.
struct PortfolioCurve {
    let scope: PortfolioScope
    let range: IBKREquityRange
    private(set) var points: [PortfolioCurvePoint] = []
    /// Deposits and withdrawals in the range, each anchored to the first point that includes it.
    private(set) var flows: [AssetTrendMarker] = []
    /// How the relay worked the figures out (shown under the chart).
    private(set) var warnings: [String] = []
    /// The real IBKR curve is used (else the built-in one).
    private(set) var isReal = false
    /// The range's P&L and return (time-weighted for 个人; P&L over the starting value for 全部), real curve only.
    private(set) var rangePnL: Double?
    private(set) var rangeReturn: Double?

    init(scope: PortfolioScope, range: IBKREquityRange = .standard) {
        self.scope = scope
        self.range = range
        if Portfolio.hasRealHistory(scope, range: range), let document = IBKREquityStore.shared.document(range),
           makeReal(document) {
            return
        }
        makeBuiltIn()
    }

    /// The largest fall from a high, as a fraction.
    var maxDrawdown: Double { points.map(\.drawdown).max() ?? 0 }

    /// Return over the curve minus the benchmark's, as a fraction.
    var excessReturn: Double {
        guard let last = points.last else { return 0 }
        return last.growth - last.benchmark
    }

    /// How the chart writes the dates: report days in UTC, intraday points as local times, the built-in curve as
    /// New York days (as it always was).
    var dateStyle: AssetTrendDateStyle {
        guard isReal else { return .builtIn }
        switch range {
        case .day: return .time
        case .week: return .dayTime
        default: return .day(TimeZone(identifier: "UTC") ?? .gmt)
        }
    }

    /// At most `limit` points (first and last kept) for drawing: a 1天 range has a point a minute.
    func chartPoints(limit: Int = 240) -> [PortfolioCurvePoint] {
        guard points.count > limit, limit > 1 else { return points }
        let step = Double(points.count - 1) / Double(limit - 1)
        return (0..<limit).map { points[Int((Double($0) * step).rounded())] }
    }

    // MARK: Real

    private mutating func makeReal(_ document: IBKREquity) -> Bool {
        let valued = document.valued.compactMap { point -> (date: Date, point: IBKREquityPoint, nav: Double)? in
            guard let date = point.date, let nav = point.nav else { return nil }
            return (date, point, nav)
        }
        guard valued.count >= 2 else { return false }
        // 全部 adds the quant account's (built-in) value, held level over the range.
        let quant = scope == .all ? Portfolio.total(.quant) : 0
        let start = valued[0].nav + quant
        let raw = valued.map { entry -> Double in
            if scope == .personal, let twr = entry.point.twr_cum { return 1 + twr }
            if let pnl = entry.point.pnl_cum, start > 0 { return 1 + pnl / start }
            return start > 0 ? (entry.nav + quant) / start : 1
        }
        let base = raw[0] > 0 ? raw[0] : 1
        let first = valued[0].date
        var peak = 0.0
        points = valued.enumerated().map { index, entry in
            let growth = raw[index] / base
            peak = max(peak, growth)
            let benchmark = Self.benchmarkGrowth(days: entry.date.timeIntervalSince(first) / 86_400)
            return PortfolioCurvePoint(id: index, date: entry.date, value: entry.nav + quant, growth: growth,
                                       benchmark: benchmark, benchmarkValue: start * benchmark,
                                       drawdown: peak > 0 ? (peak - growth) / peak : 0)
        }
        flows = Self.anchored(document.flows, to: points, intraday: range.isIntraday)
        warnings = document.warnings
        isReal = true
        let lastGrowth = points.last?.growth ?? 1
        rangePnL = document.pnl ?? ((points.last?.value ?? 0) - (points.first?.value ?? 0))
        rangeReturn = scope == .personal ? (document.twr ?? lastGrowth - 1) : lastGrowth - 1
        return true
    }

    /// The relay has no benchmark: a built-in one rising about 10 % a year.
    private static func benchmarkGrowth(days: Double) -> Double { pow(1.10, max(0, days) / 365) }

    /// Each flow on the first point that includes it: the first report day on or after the flow's day (UTC), or the
    /// first intraday point at or after it; past the last point, the last one.
    private static func anchored(_ flows: [IBKREquityFlow], to points: [PortfolioCurvePoint],
                                 intraday: Bool) -> [AssetTrendMarker] {
        guard let last = points.last else { return [] }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return flows.compactMap { flow in
            guard let date = flow.date, flow.amount != 0 else { return nil }
            let anchor = points.first { point in
                intraday ? point.date >= date : utc.startOfDay(for: point.date) >= utc.startOfDay(for: date)
            } ?? last
            return AssetTrendMarker(id: flow.id, date: anchor.date, title: flow.title, amount: flow.amount)
        }
    }

    // MARK: Built in

    private mutating func makeBuiltIn() {
        let all = Portfolio.points(scope, range: range)
        // The built-in curve is 30 days: 1天 and 1周 show its last days, the longer ranges all of it.
        let shown: [DemoPoint] = switch range {
        case .day: Array(all.suffix(2))
        case .week: Array(all.suffix(7))
        default: all
        }
        guard let first = shown.first else { return }
        let live = Portfolio.isLive
        // Once paired the built-in curve ends at the real total (its shape is built in); before pairing it is drawn
        // exactly as it always was.
        let scale = live && (shown.last?.equity ?? 0) > 0 ? Portfolio.total(scope) / (shown.last?.equity ?? 1) : 1
        points = shown.enumerated().map { index, point in
            PortfolioCurvePoint(id: index, date: point.date, value: point.equity * scale,
                                growth: first.equity > 0 ? point.equity / first.equity : 1,
                                benchmark: first.benchmark > 0 ? point.benchmark / first.benchmark : 1,
                                benchmarkValue: point.benchmark * scale, drawdown: point.drawdown)
        }
        // Once paired the built-in curve carries the built-in deposit too (10 月 20 日, 个人), so the chart shows
        // how a flow is marked.
        if live, scope != .quant, let anchor = points.min(by: {
            abs($0.date.timeIntervalSince(Self.builtInDeposit)) < abs($1.date.timeIntervalSince(Self.builtInDeposit))
        }), abs(anchor.date.timeIntervalSince(Self.builtInDeposit)) < 43_200 {
            flows = [AssetTrendMarker(id: "builtin-deposit", date: anchor.date, title: "入金", amount: 1_000)]
        }
    }

    private static var builtInDeposit: Date { DemoPortfolioData.date.addingTimeInterval(-3 * 86_400) }
}

extension View {
    /// Once paired: reads the IBKR value curve over `range` now, then every 10 s (a 304 when nothing changed), while
    /// this view is on screen and the window in front (`active`); restarted when the range or pairing changes.
    func pollsIBKREquity(_ range: IBKREquityRange, active: Bool) -> some View {
        task(id: IBKREquityPolling(range: range, active: active, live: Portfolio.isLive)) {
            guard active, Portfolio.isLive else { return }
            await IBKREquityStore.shared.runPolling(range)
        }
    }
}

/// What restarts the value curve's polling.
private struct IBKREquityPolling: Equatable {
    var range: IBKREquityRange
    var active: Bool
    var live: Bool
}
