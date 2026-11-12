import SwiftUI
import Charts
import PortSightKit

/// Strategy signals under the price chart, on the same time window: each signal as a line, entry and exit
/// thresholds dashed, so "opened the moment it crossed, closed the moment it dipped" is easy to see.
struct BacktestSignalChart: View {
    let model: BacktestViewerModel

    var body: some View {
        let points = model.visibleSignals()
        let keys = Array(Set(points.flatMap(\.values.keys))).sorted()
        Chart {
            RuleMark(y: .value("零", 0)).foregroundStyle(.primary.opacity(0.15))
            ForEach(keys, id: \.self) { key in
                let threshold = BacktestSignalPoint.isThreshold(key)
                ForEach(points, id: \.t) { point in
                    if let value = point.values[key] {
                        LineMark(x: .value("时间", point.date), y: .value("值", value), series: .value("信号", key))
                            .foregroundStyle(by: .value("信号", key))
                            .lineStyle(StrokeStyle(lineWidth: threshold ? 1 : 1.4, dash: threshold ? [4, 3] : []))
                        if threshold {
                            // Mirrored threshold for short entries and exits.
                            LineMark(x: .value("时间", point.date), y: .value("值", -value), series: .value("信号", "-" + key))
                                .foregroundStyle(by: .value("信号", key))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                                .opacity(0.6)
                        }
                    }
                }
            }
        }
        .chartXScale(domain: Date(milliseconds: model.window.lowerBound)...Date(milliseconds: model.window.upperBound))
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
        .chartLegend(position: .top, alignment: .leading, spacing: 4)
        .chartPlotStyle { $0.clipped() }
        .overlay {
            if points.isEmpty {
                Text("这个回测没有导出信号").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Net asset value (with the benchmark and the compared run) over drawdown; clicking a day moves the price chart
/// there, and the price chart's window is shaded.
struct BacktestEquityChart: View {
    let model: BacktestViewerModel

    var body: some View {
        let equity = model.run.equity
        let compared = model.compareRun?.equity ?? []
        VStack(spacing: 6) {
            Chart {
                ForEach(equity, id: \.t) { point in
                    LineMark(x: .value("日期", point.date), y: .value("净值", point.nav), series: .value("曲线", "nav"))
                        .foregroundStyle(by: .value("曲线", model.run.meta.strategy))
                    if let bench = point.benchNav {
                        LineMark(x: .value("日期", point.date), y: .value("净值", bench), series: .value("曲线", "bench"))
                            .foregroundStyle(by: .value("曲线", "基准"))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                ForEach(compared, id: \.t) { point in
                    LineMark(x: .value("日期", point.date), y: .value("净值", point.nav), series: .value("曲线", "compare"))
                        .foregroundStyle(by: .value("曲线", model.compareRun?.meta.strategy ?? "对比"))
                }
            }
            .chartForegroundStyleScale(domain: legendDomain, range: legendRange)
            .chartLegend(position: .top, alignment: .leading)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) }
            .chartOverlay { proxy in
                ZStack {
                    BacktestWindowShade(model: model, proxy: proxy)
                    tapLayer(proxy)
                }
            }
            .frame(height: 190)

            Chart(equity, id: \.t) { point in
                AreaMark(x: .value("日期", point.date), y: .value("回撤", point.dd))
                    .foregroundStyle(.red.opacity(0.25))
                LineMark(x: .value("日期", point.date), y: .value("回撤", point.dd))
                    .foregroundStyle(.red.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1))
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel { if let dd = value.as(Double.self) { Text(BacktestFormat.plainPercent(dd, digits: 0)) } }
                }
            }
            .chartOverlay { proxy in tapLayer(proxy) }
            .frame(height: 80)
        }
    }

    private var legendDomain: [String] {
        [model.run.meta.strategy, "基准"] + (model.compareRun.map { [$0.meta.strategy] } ?? [])
    }

    private var legendRange: [Color] {
        [DesktopTheme.blue, .secondary] + (model.compareRun == nil ? [] : [.purple])
    }

    private func tapLayer(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            let plot = proxy.plotFrame.map { geometry[$0] } ?? .zero
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onTapGesture { location in
                    if let date: Date = proxy.value(atX: location.x - plot.minX) { model.jump(to: date.milliseconds) }
                }
        }
    }
}

/// The price chart's current window, shaded on the equity chart. A view of its own so that panning the price
/// chart only redraws this rectangle, not the whole equity curve.
private struct BacktestWindowShade: View {
    let model: BacktestViewerModel
    let proxy: ChartProxy

    var body: some View {
        GeometryReader { geometry in
            if let frame = proxy.plotFrame.map({ geometry[$0] }),
               let x0 = proxy.position(forX: Date(milliseconds: model.window.lowerBound)),
               let x1 = proxy.position(forX: Date(milliseconds: model.window.upperBound)) {
                let left = max(frame.minX + x0, frame.minX), right = min(frame.minX + x1, frame.maxX)
                if right > left {
                    Rectangle().fill(DesktopTheme.blue.opacity(0.08))
                        .frame(width: right - left, height: frame.height)
                        .position(x: (left + right) / 2, y: frame.midY)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Details of the clicked trade.
struct BacktestTradeDetail: View {
    let trade: BacktestTrade
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trade.symbol + " · " + trade.side.title).font(.system(size: 15, weight: .semibold))
                    Text(trade.id).font(.system(size: 11)).foregroundStyle(.secondary).monospaced()
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .accessibilityLabel("关闭详情")
            }
            Text(BacktestFormat.percent(trade.pnlNet, digits: 3))
                .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(DesktopTheme.pnlColor(trade.pnlNet))
            Text("净收益（占净值）· " + trade.exitTitle).font(.system(size: 11)).foregroundStyle(.secondary)
            if !trade.hasPrices {
                Label("导出里缺开仓或平仓价，K 线上不画这笔的框", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(DesktopTheme.orange)
            }
            if trade.enteredInLockbox == false {
                Label("开仓早于考试段：净收益只算考试段内的部分，和开平仓价算出的涨跌对不上", systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                row("开仓", trade.entryPriceText + " · " + BacktestFormat.time(trade.entryT))
                row("平仓", trade.exitPriceText + " · " + BacktestFormat.time(trade.exitT))
                row("持有", BacktestFormat.hours(trade.holdH) + (trade.extensions.map { $0 > 0 ? " · 延长 \($0) 次" : "" } ?? ""))
                row("毛收益", Self.percent(trade.reportedPnlGross))
                row("手续费", Self.percent(trade.reportedFee.map { -$0 }))
                row("资金费", Self.percent(trade.reportedFunding))
                row("最大浮盈", Self.percent(trade.reportedMfe))
                row("最大浮亏", Self.percent(trade.reportedMae))
                if let hedge = trade.hedge, !hedge.symbol.isEmpty {
                    row("对冲", hedge.symbol + (hedge.side.map { " " + $0.title } ?? "")
                        + (hedge.w.map { " " + BacktestFormat.plainPercent(abs($0)) } ?? ""))
                }
            }
            .font(.system(size: 12)).monospacedDigit()
            if !trade.signalsAtEntry.isEmpty {
                Divider()
                Text("开仓时信号").font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(trade.signalsAtEntry.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key).monospaced()
                        Spacer()
                        Text(String(format: "%.4f", trade.signalsAtEntry[key] ?? 0)).monospacedDigit()
                    }
                    .font(.system(size: 12))
                }
            }
            if trade.sizePath.count > 1 {
                Divider()
                Text("仓位变化").font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(Array(trade.sizePath.enumerated()), id: \.offset) { _, step in
                    HStack {
                        Text(trade.title(of: step))
                        Spacer()
                        Text(BacktestFormat.plainPercent(abs(step.w)) + " · " + BacktestFormat.time(step.t))
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11)).monospacedDigit()
                }
            }
        }
        .padding(16)
        .frame(width: 290, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// A P&L part, or "—" when the export left it out.
    static func percent(_ value: Double?) -> String {
        value.map { BacktestFormat.percent($0, digits: 3) } ?? "—"
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

/// Key figures for the run and each year.
struct BacktestMetricsPanel: View {
    let run: BacktestRun

    var body: some View {
        let overall = run.metrics.overall
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 24) {
                DesktopStat(label: "夏普（90% 区间）", value: String(format: "%.2f", overall.sharpe),
                            detail: String(format: "%.2f – %.2f", overall.sharpeLow, overall.sharpeHigh),
                            tint: overall.sharpeLow > 0 ? DesktopTheme.green : .primary)
                DesktopStat(label: "年化", value: BacktestFormat.percent(overall.annualReturn, digits: 1),
                            tint: DesktopTheme.pnlColor(overall.annualReturn))
                DesktopStat(label: "最大回撤", value: BacktestFormat.plainPercent(overall.maxDrawdown), tint: .red)
                DesktopStat(label: "胜率", value: BacktestFormat.plainPercent(overall.winRate), detail: "\(overall.trades) 笔")
                DesktopStat(label: "平均持有", value: BacktestFormat.hours(overall.averageHoldHours))
                DesktopStat(label: "年换手", value: String(format: "%.1f×", overall.annualTurnover))
                DesktopStat(label: "手续费 / 毛收益", value: overall.feeShare.map { BacktestFormat.plainPercent($0) } ?? "—")
            }
            Grid(alignment: .trailing, horizontalSpacing: 26, verticalSpacing: 8) {
                GridRow {
                    Text("年份").gridColumnAlignment(.leading)
                    Text("收益"); Text("夏普"); Text("最大回撤"); Text("胜率"); Text("交易"); Text("平均持有"); Text("手续费占比")
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
                ForEach(run.metrics.byYear) { year in
                    GridRow {
                        Text(year.title).fontWeight(.medium)
                        Text(BacktestFormat.percent(year.annualReturn, digits: 1)).foregroundStyle(DesktopTheme.pnlColor(year.annualReturn))
                        Text(String(format: "%.2f", year.sharpe))
                        Text(BacktestFormat.plainPercent(year.maxDrawdown)).foregroundStyle(.red)
                        Text(BacktestFormat.plainPercent(year.winRate))
                        Text("\(year.trades)")
                        Text(BacktestFormat.hours(year.averageHoldHours))
                        Text(year.feeShare.map { BacktestFormat.plainPercent($0) } ?? "—")
                    }
                    .font(.system(size: 12)).monospacedDigit()
                }
            }
            Text("年份收益按当年净值变化计算（不足一年的按实际天数折算）；夏普用\(run.metrics.samplingTitle)收益、按 365 天年化，区间按 Lo (2002) 标准误。手续费占比只算导出了毛收益和手续费的交易。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

/// Every trade, sortable and filterable; selecting one moves the price chart to it.
struct BacktestTradeTable: View {
    @Bindable var model: BacktestViewerModel
    @State private var sortOrder = [KeyPathComparator(\BacktestTrade.entryT, order: .reverse)]

    var body: some View {
        let rows = model.listedTrades.sorted(using: sortOrder)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                DesktopCapsulePicker(title: "快速筛选", options: BacktestQuickFilter.allCases, selection: $model.quickFilter) { $0.rawValue }.labelsHidden().fixedSize()
                Spacer()
                DesktopCapsuleMenu(title: "品种", value: model.listSymbol ?? "全部品种", selection: $model.listSymbol) {
                    Text("全部品种").tag(String?.none)
                    ForEach(model.run.symbols, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .fixedSize()
                DesktopCapsuleMenu(title: "方向", value: model.listSide?.title ?? "多空", selection: $model.listSide) {
                    Text("多空").tag(BacktestSide?.none)
                    Text("多").tag(BacktestSide?.some(.long))
                    Text("空").tag(BacktestSide?.some(.short))
                }
                .fixedSize()
                DesktopCapsuleMenu(title: "平仓原因", value: model.listReason.map { BacktestExitReason.title($0) } ?? "全部原因", selection: $model.listReason) {
                    Text("全部原因").tag(String?.none)
                    ForEach(model.exitReasons, id: \.self) { Text(BacktestExitReason.title($0)).tag(String?.some($0)) }
                }
                .fixedSize()
            }
            .labelsHidden()
            .controlSize(.small)

            Table(rows, selection: Binding(get: { model.selectedTradeID }, set: { id in
                if let id, let trade = model.run.trades.first(where: { $0.id == id }) { model.focus(trade) }
            }), sortOrder: $sortOrder) {
                TableColumn("编号", value: \.id) { Text($0.id).monospaced() }.width(min: 90, ideal: 100)
                TableColumn("品种", value: \.symbol).width(min: 70, ideal: 80)
                TableColumn("方向", value: \.side.rawValue) { trade in
                    Text(trade.side.title).foregroundStyle(trade.side == .long ? DesktopTheme.green : .red)
                }
                .width(44)
                TableColumn("开仓", value: \.entryT) { Text(BacktestFormat.time($0.entryT)).monospacedDigit() }.width(min: 130, ideal: 140)
                TableColumn("开 → 平") { trade in
                    Text(trade.entryPriceText + " → " + trade.exitPriceText).monospacedDigit()
                        .foregroundStyle(trade.hasPrices ? .primary : .secondary)
                }
                .width(min: 110, ideal: 140)
                TableColumn("持有", value: \.holdH) { Text(BacktestFormat.hours($0.holdH)).monospacedDigit() }.width(70)
                TableColumn("平仓原因", value: \.exitReason) { Text($0.exitTitle) }.width(70)
                TableColumn("净收益", value: \.pnlNet) { trade in
                    Text(BacktestFormat.percent(trade.pnlNet, digits: 3)).monospacedDigit()
                        .foregroundStyle(DesktopTheme.pnlColor(trade.pnlNet))
                }
                .width(80)
                TableColumn("最大浮盈", value: \.mfe) { Text(BacktestTradeDetail.percent($0.reportedMfe)).monospacedDigit() }.width(80)
                TableColumn("最大浮亏", value: \.mae) { Text(BacktestTradeDetail.percent($0.reportedMae)).monospacedDigit() }.width(80)
            }
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("\(rows.count) 笔 · 点击一行，K 线跳到那笔交易").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
