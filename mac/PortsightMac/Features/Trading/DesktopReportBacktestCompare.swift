import SwiftUI
import Charts
import PortSightKit

/// Crypto forward seal for trading lines: a shadow ledger shows status, counts and checks only from 2026-10-22,
/// and its returns and comparisons open again on 2027-05-06. Paper and live accounts are never sealed.
enum DesktopLineSeal {
    static let start = BacktestRun.sealStart
    static let opens = Date(timeIntervalSince1970: 1_809_561_600) // 2027-05-06 00:00 UTC
    static let opensTitle = "2027-05-06"

    static func isSealed(_ line: TradingLine, now: Date = .now) -> Bool {
        line.mode == .shadow && now >= start && now < opens
    }
}

/// What a backtest says a line should do over a window of `days` days: the 10 / 50 / 90 percentile growth path
/// over every same-length window of its daily NAV, the spread of window returns and drawdowns, and trade stats.
struct BacktestExpectation {
    let days: Int
    let low: [Double]
    let median: [Double]
    let high: [Double]
    /// Window returns and max drawdowns (positive), sorted ascending.
    let returns: [Double]
    let drawdowns: [Double]
    let winRate: Double
    let tradesPerWeek: Double

    var expectedReturn: Double { Self.quantile(returns, 0.5) }
    var returnLow: Double { Self.quantile(returns, 0.1) }
    var returnHigh: Double { Self.quantile(returns, 0.9) }
    var expectedDrawdown: Double { Self.quantile(drawdowns, 0.5) }
    var drawdownHigh: Double { Self.quantile(drawdowns, 0.9) }

    /// Share of backtest windows whose return was below `value`.
    func rank(_ value: Double) -> Double {
        guard !returns.isEmpty else { return 0.5 }
        return Double(returns.filter { $0 < value }.count) / Double(returns.count)
    }

    private static var cache: [String: BacktestExpectation] = [:]

    static func of(_ run: BacktestRun, days: Int) -> BacktestExpectation? {
        let key = run.id + "#\(days)"
        if let cached = cache[key] { return cached }
        guard let value = BacktestExpectation(run: run, days: days) else { return nil }
        cache[key] = value
        return value
    }

    private init?(run: BacktestRun, days: Int) {
        // Last NAV of each UTC day.
        var byDay: [Int: Double] = [:]
        for point in run.equity { byDay[Int(point.t / 86_400_000)] = point.nav }
        let nav = byDay.keys.sorted().compactMap { byDay[$0] }
        guard days > 0, nav.count > days + 10 else { return nil }

        var paths = Array(repeating: [Double](), count: days)
        var returns: [Double] = [], drawdowns: [Double] = []
        for start in 0..<(nav.count - days) where nav[start] > 0 {
            let base = nav[start]
            // Peak starts at the window's start NAV (1.0), the same definition as TradingReport.maxDrawdown.
            var peak = 1.0, worst = 0.0
            for k in 0..<days {
                let growth = nav[start + k + 1] / base
                paths[k].append(growth)
                peak = max(peak, growth)
                worst = max(worst, (peak - growth) / peak)
            }
            returns.append(nav[start + days] / base - 1)
            drawdowns.append(worst)
        }
        let sorted = paths.map { $0.sorted() }
        self.days = days
        low = sorted.map { Self.quantile($0, 0.1) }
        median = sorted.map { Self.quantile($0, 0.5) }
        high = sorted.map { Self.quantile($0, 0.9) }
        self.returns = returns.sorted()
        self.drawdowns = drawdowns.sorted()

        let trades = run.trades
        winRate = trades.isEmpty ? 0 : Double(trades.filter(\.isWin).count) / Double(trades.count)
        let spanDays = max(1, ((run.equity.last?.t ?? 0) - (run.equity.first?.t ?? 0)) / 86_400_000)
        tradesPerWeek = Double(trades.count) / (spanDays / 7)
    }

    static func quantile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let position = q * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down)), upper = Int(position.rounded(.up))
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }
}

/// 在预期范围内 / 偏弱 / 偏强: where the actual window return falls in the backtest's distribution.
enum BacktestDrift {
    case inRange, weak, strong

    init(actualReturn: Double, actualDrawdown: Double, expectation: BacktestExpectation) {
        let rank = expectation.rank(actualReturn)
        if rank < 0.1 || actualDrawdown > expectation.drawdownHigh { self = .weak }
        else if rank > 0.9 { self = .strong }
        else { self = .inRange }
    }

    var title: String {
        switch self {
        case .inRange: "在预期范围内"
        case .weak: "偏弱"
        case .strong: "偏强"
        }
    }

    var icon: String {
        switch self {
        case .inRange: "checkmark.circle.fill"
        case .weak: "arrow.down.circle.fill"
        case .strong: "arrow.up.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .inRange: DesktopTheme.green
        case .weak: DesktopTheme.orange
        case .strong: DesktopTheme.blue
        }
    }
}

/// 复盘 · 和回测比: the line's last 30 days of running NAV against the spread its backtest expects.
struct DesktopReportBacktestCompare: View {
    let line: TradingLine
    var showsDivider = true

    /// The backtest runs to compare with (the built-in set until exported runs are connected).
    static let runs: [BacktestRun] = BacktestSample.runs()

    @State private var pickedRunID: String?
    @State private var hovered: Date?

    private var sealed: Bool { DesktopLineSeal.isSealed(line) }
    private var report: TradingReport { line.weekly }
    private var match: (run: BacktestRun, byName: Bool)? { Self.closestRun(for: line) }
    private var run: BacktestRun? {
        if let pickedRunID, let picked = Self.runs.first(where: { $0.id == pickedRunID }) { return picked }
        return match?.run
    }

    var body: some View {
        DesktopPageSection(title: "和回测比", subtitle: subtitle, showsDivider: showsDivider) {
            if sealed {
                Label("影子账本在前向封存期，和回测的对照 \(DesktopLineSeal.opensTitle) 开放。", systemImage: "lock")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            } else if let run, let expectation = BacktestExpectation.of(run, days: report.points.count),
                      report.points.count >= 5 {
                comparison(run: run, expectation: expectation)
            } else {
                Text("近 30 天的净值或回测数据不够，暂时比不了。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        } trailing: {
            if !sealed, !Self.runs.isEmpty {
                DesktopCapsuleMenu(title: "回测", value: Self.runs.first { $0.id == runBinding.wrappedValue }.map { $0.meta.strategy + " · " + $0.meta.segmentTitle } ?? "选择回测", selection: runBinding) {
                    ForEach(Self.runs) { run in
                        Text(run.meta.strategy + " · " + run.meta.segmentTitle).tag(run.id)
                    }
                }.labelsHidden().fixedSize()
                .help("选择用来对照的回测")
            }
        }
    }

    private var subtitle: String {
        if sealed { return "封存期只看状态和检验" }
        guard let run else { return "没有可用的回测" }
        if pickedRunID == nil, match?.byName == false {
            return "没有同名回测，先用 \(run.meta.strategy)，可在右侧换"
        }
        return "近 \(report.points.count) 天对照 \(run.meta.strategy)（\(run.meta.verdictKind.rawValue)）"
    }

    private var runBinding: Binding<String> {
        Binding(get: { run?.id ?? "" }, set: { pickedRunID = $0 })
    }

    // MARK: Comparison

    @ViewBuilder private func comparison(run: BacktestRun, expectation: BacktestExpectation) -> some View {
        let actualReturn = report.returnPct
        let actualDrawdown = report.maxDrawdown
        let drift = BacktestDrift(actualReturn: actualReturn, actualDrawdown: actualDrawdown, expectation: expectation)
        let rank = expectation.rank(actualReturn)

        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(drift.title, systemImage: drift.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(drift.color)
                .contentTransition(.symbolEffect(.replace))
            Text("实际收益高于回测里 \(Int((rank * 100).rounded()))% 的同长度区间")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .monospacedDigit().contentTransition(.numericText(value: rank))
        }

        metricsGrid(expectation: expectation, actualReturn: actualReturn, actualDrawdown: actualDrawdown)

        chart(expectation: expectation)
        HStack(spacing: 18) {
            Label("实际", systemImage: "line.diagonal").foregroundStyle(DesktopTheme.blue)
            Label("回测中位", systemImage: "line.diagonal").foregroundStyle(.secondary)
            Label("回测 10%–90% 区间", systemImage: "square.fill").foregroundStyle(.secondary.opacity(0.5))
        }
        .font(.system(size: 11))
    }

    private func metricsGrid(expectation: BacktestExpectation, actualReturn: Double, actualDrawdown: Double) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 36, verticalSpacing: 10) {
            GridRow {
                Text("指标"); Text("回测预期"); Text("回测区间"); Text("实际"); Text("差")
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
            GridRow {
                Text("收益（近 \(expectation.days) 天）")
                value(TerminalFormat.percent(expectation.expectedReturn), expectation.expectedReturn)
                Text(TerminalFormat.percent(expectation.returnLow) + " ~ " + TerminalFormat.percent(expectation.returnHigh))
                    .foregroundStyle(.secondary).monospacedDigit()
                value(TerminalFormat.percent(actualReturn), actualReturn)
                    .foregroundStyle(DesktopTheme.pnlColor(actualReturn))
                value(TerminalFormat.percent(actualReturn - expectation.expectedReturn), actualReturn - expectation.expectedReturn)
                    .foregroundStyle(DesktopTheme.pnlColor(actualReturn - expectation.expectedReturn))
            }
            GridRow {
                Text("最大回撤")
                value(TerminalFormat.percent(-expectation.expectedDrawdown), expectation.expectedDrawdown)
                Text("最差 10%：" + TerminalFormat.percent(-expectation.drawdownHigh))
                    .foregroundStyle(.secondary).monospacedDigit()
                value(TerminalFormat.percent(-actualDrawdown), actualDrawdown)
                value(TerminalFormat.percent(expectation.expectedDrawdown - actualDrawdown), actualDrawdown - expectation.expectedDrawdown)
                    .foregroundStyle(DesktopTheme.pnlColor(expectation.expectedDrawdown - actualDrawdown))
            }
            GridRow {
                Text("胜率")
                value(TerminalFormat.percent(expectation.winRate, signed: false), expectation.winRate)
                Text("按回测全部交易").foregroundStyle(.secondary)
                DesktopPendingLabel(text: "成交记录尚未接入")
                Text("—").foregroundStyle(.secondary)
            }
            GridRow {
                Text("每周交易")
                value(expectation.tradesPerWeek.formatted(.number.precision(.fractionLength(1))) + " 笔", expectation.tradesPerWeek)
                Text("按回测全部交易").foregroundStyle(.secondary)
                DesktopPendingLabel(text: "成交记录尚未接入")
                Text("—").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
    }

    private func value(_ text: String, _ number: Double) -> some View {
        Text(text).monospacedDigit().contentTransition(.numericText(value: number))
    }

    private func chart(expectation: BacktestExpectation) -> some View {
        let points = Array(report.points.prefix(expectation.days))
        return Chart {
            ForEach(Array(points.enumerated()), id: \.element.id) { k, point in
                AreaMark(x: .value("日期", point.date),
                         yStart: .value("下沿", expectation.low[k]), yEnd: .value("上沿", expectation.high[k]))
                    .foregroundStyle(Color.secondary.opacity(0.14)).interpolationMethod(.catmullRom)
                LineMark(x: .value("日期", point.date), y: .value("净值", expectation.median[k]), series: .value("曲线", "回测"))
                    .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("日期", point.date), y: .value("净值", point.equity), series: .value("曲线", "实际"))
                    .foregroundStyle(DesktopTheme.blue).lineStyle(StrokeStyle(lineWidth: 2.2))
                    .interpolationMethod(.catmullRom)
            }
            if let hovered, let k = points.indices.min(by: {
                abs(points[$0].date.timeIntervalSince(hovered)) < abs(points[$1].date.timeIntervalSince(hovered))
            }) {
                RuleMark(x: .value("日期", points[k].date))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, alignment: .leading) {
                        Text(points[k].date.formatted(.dateTime.month().day())
                             + "  实际 " + TerminalFormat.percent(points[k].equity - 1)
                             + " · 回测 " + TerminalFormat.percent(expectation.median[k] - 1))
                            .font(.system(size: 11, weight: .medium)).monospacedDigit()
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.regularMaterial, in: Capsule())
                    }
            }
        }
        .chartXSelection(value: $hovered)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis { AxisMarks { value in
            AxisGridLine().foregroundStyle(.separator)
            AxisValueLabel { if let v = value.as(Double.self) { Text(TerminalFormat.percent(v - 1)) } }
        } }
        .chartLegend(.hidden)
        .frame(height: 240)
    }

    // MARK: Matching a line to a run

    /// The run whose strategy name or id shares the most words with the line; otherwise, for a crypto line, the
    /// first crypto run that passed; otherwise the first run that passed.
    static func closestRun(for line: TradingLine) -> (run: BacktestRun, byName: Bool)? {
        let words = tokens(line.title + " " + line.id)
        let scored = runs.map { run in
            (run, tokens(run.meta.strategy + " " + run.meta.runID).intersection(words).count)
        }
        if let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 { return (best.0, true) }
        let isCrypto = line.id.lowercased().contains("crypto") || line.caption.uppercased().contains("CRYPTO")
        let candidates = isCrypto ? runs.filter { $0.symbols.contains { $0.hasSuffix("USDT") } } : runs
        let pool = candidates.isEmpty ? runs : candidates
        guard let pick = pool.first(where: { $0.meta.verdictKind == .pass }) ?? pool.first else { return nil }
        return (pick, false)
    }

    private static func tokens(_ text: String) -> Set<String> {
        let ignored: Set<String> = ["v", "arm0", "run", "line"]
        return Set(text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 && !ignored.contains($0) })
    }
}
