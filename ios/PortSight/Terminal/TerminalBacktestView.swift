//
//  TerminalBacktestView.swift
//  PortSight
//
//  交易 · 回测 on iPhone: the Mac 回测 viewer on the same PortSightKit model (BacktestViewerModel). Run and symbol
//  menus, K-line with one box per trade, equity and drawdown, metrics, and the trade list with quick filters.
//  Read-only: it never runs a backtest, never orders and holds no keys. Data from 2026-10-22 on stays sealed
//  (BacktestRun drops it).
//

import SwiftUI
import Charts
import PortSightKit

/// Builds the viewer model once, on first appearance. KeptAlivePages re-creates this struct on every page switch,
/// and `@State var model = BacktestViewerModel()` would rebuild the sample runs each time only to throw them away.
struct TerminalBacktestView: View {
    @State private var model: BacktestViewerModel?

    var body: some View {
        if let model {
            TerminalBacktestContent(model: model)
        } else {
            NavigationStack {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .portSightBackdrop()
                    .toolbar { DemoToolbar(showsScope: false) }
            }
            .task { if model == nil { model = BacktestViewerModel() } }
        }
    }
}

private struct TerminalBacktestContent: View {
    @Bindable var model: BacktestViewerModel
    @State private var detailTrade: BacktestTrade?
    @State private var sort: TradeSort = .newest

    private static let chartID = "backtest-kline"

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                PortSightList {
                    heroSection
                    chartSection
                        .id(Self.chartID)
                    Section {
                        TerminalBacktestEquityChart(model: model) {
                            withAnimation(.smooth) { scroller.scrollTo(Self.chartID, anchor: .top) }
                        }
                        .padding(.vertical, 6)
                    } header: {
                        Text("资金曲线与回撤")
                    } footer: {
                        Text("点一下某天，K 线跳到那天。")
                    }
                    metricsSection
                    yearsSection
                    tradesSection { trade in
                        model.focus(trade)
                        withAnimation(.smooth) { scroller.scrollTo(Self.chartID, anchor: .top) }
                    }
                }
                .terminalPageList()
                .toolbar { DemoToolbar(showsScope: false) }
                .animation(.smooth, value: model.runID)
                .animation(.smooth, value: model.quickFilter)
                .sensoryFeedback(.selection, trigger: model.runID)
                .sensoryFeedback(.selection, trigger: model.symbol)
                .sheet(item: $detailTrade) { trade in
                    TerminalBacktestTradeSheet(trade: trade, bars: sheetBars(for: trade))
                        .presentationDetents([.medium, .large])
                }
            }
        }
    }

    /// Bars for a trade's path chart: the finest timeframe with at least a few bars across the trade (a 40-minute
    /// stop-out has no 4h bar start inside it), else the page's timeframe.
    private func sheetBars(for trade: BacktestTrade) -> [BacktestBar] {
        let length = max(trade.exitT - trade.entryT, 1)
        let from = trade.entryT - length * 0.25, to = trade.exitT + length * 0.25
        for timeframe in model.run.timeframes(trade.symbol) {
            let bars = model.run.bars(trade.symbol, timeframe)
            let low = BacktestViewerModel.index(in: bars, atOrBefore: from)
            let high = BacktestViewerModel.index(in: bars, atOrBefore: to)
            if high - low >= 3 { return bars }
        }
        return model.run.bars(trade.symbol, model.timeframe)
    }

    // MARK: Header

    private var heroSection: some View {
        let meta = model.run.meta
        let overall = model.run.metrics.overall
        return Section {
            TerminalHero(eyebrow: meta.strategy + " · 年化", value: BacktestFormat.percent(overall.annualReturn, digits: 1),
                         detail: meta.runID) {
                VStack(alignment: .leading, spacing: 10) {
                    Menu {
                        Picker("回测", selection: Binding(get: { model.runID }, set: { model.changeRun($0) })) {
                            ForEach(model.runs) { run in
                                Text(run.meta.strategy + " · " + run.meta.runID).tag(run.id)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label("选择回测", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.bordered)
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            pill(meta.verdictKind.rawValue + " · " + meta.verdict, tint: verdictTint(meta.verdictKind))
                            pill(meta.segmentTitle, tint: .blue)
                            pill(BacktestFormat.time(meta.start).prefix(10) + " – " + BacktestFormat.time(meta.end).prefix(10), tint: .secondary)
                            pill(meta.costModel, tint: .secondary)
                            if model.run.directory == nil { pill("内置样例", tint: .orange) }
                        }
                    }
                    .scrollIndicators(.hidden)
                    if let notes = meta.notes, !notes.isEmpty {
                        Text(notes).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .terminalHeroRow()
        }
    }

    private func verdictTint(_ verdict: BacktestVerdict) -> Color {
        switch verdict {
        case .pass: .green
        case .fail: .red
        case .reportOnly: .secondary
        }
    }

    private func pill(_ text: some StringProtocol, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }

    // MARK: K-line

    private var chartSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    symbolPicker
                    Spacer(minLength: 0)
                    zoomButtons
                }
                Picker("周期", selection: Binding(get: { model.timeframe }, set: { model.changeTimeframe($0) })) {
                    ForEach(model.run.timeframes(model.symbol)) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                TerminalBacktestPriceChart(model: model) { trade in detailTrade = trade }
                    .frame(height: 340)
                legend
            }
            .padding(.vertical, 6)
        } header: {
            Text("K 线")
        } footer: {
            Text("每笔交易一个框：开仓价以上是盈利区，以下是亏损区，虚线从开仓连到平仓。左右拖动平移，捏合缩放，点框看详情。")
        }
    }

    /// Every symbol the run traded (or has bars for): a few fit as segments, more become a menu with trade counts.
    @ViewBuilder private var symbolPicker: some View {
        let symbols = model.run.symbols
        let selection = Binding(get: { model.symbol }, set: { model.symbol = $0; model.selectedTradeID = nil })
        if symbols.count <= 3 {
            Picker("品种", selection: selection) {
                ForEach(symbols, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        } else {
            let counts = model.tradeCounts
            Picker("品种", selection: selection) {
                ForEach(symbols, id: \.self) { symbol in
                    Text("\(symbol) · \(counts[symbol] ?? 0) 笔").tag(symbol)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private var zoomButtons: some View {
        HStack(spacing: 4) {
            Button { withAnimation(.smooth) { model.zoom(by: 1.4) } } label: { Image(systemName: "minus.magnifyingglass") }
                .accessibilityLabel("缩小")
            Button { withAnimation(.smooth) { model.zoom(by: 1 / 1.4) } } label: { Image(systemName: "plus.magnifyingglass") }
                .accessibilityLabel("放大")
            Button { withAnimation(.smooth) { model.showAll() } } label: { Image(systemName: "arrow.left.and.right") }
                .accessibilityLabel("显示全部")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.small)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            swatch(.green.opacity(0.35), "盈利区")
            swatch(.red.opacity(0.35), "亏损区")
            swatch(.blue.opacity(0.55), "仓位")
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    private func swatch(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title)
        }
    }

    // MARK: Metrics

    private var metricsSection: some View {
        let overall = model.run.metrics.overall
        return Section("指标") {
            LabeledContent("夏普（90% 区间）") {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.2f", overall.sharpe))
                        .foregroundStyle(overall.sharpeLow > 0 ? .green : .primary)
                        .contentTransition(.numericText(value: overall.sharpe))
                    Text(String(format: "%.2f – %.2f", overall.sharpeLow, overall.sharpeHigh))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            metric("年化", BacktestFormat.percent(overall.annualReturn, digits: 1), value: overall.annualReturn,
                   tint: TerminalStyle.pnl(overall.annualReturn))
            metric("最大回撤", BacktestFormat.plainPercent(overall.maxDrawdown), value: overall.maxDrawdown, tint: .red)
            metric("胜率", BacktestFormat.plainPercent(overall.winRate) + " · \(overall.trades) 笔", value: overall.winRate)
            metric("平均持有", BacktestFormat.hours(overall.averageHoldHours), value: overall.averageHoldHours)
            metric("年换手", String(format: "%.1f×", overall.annualTurnover), value: overall.annualTurnover)
            metric("手续费 / 毛收益", overall.feeShare.map { BacktestFormat.plainPercent($0) } ?? "—", value: overall.feeShare ?? 0)
        }
        .monospacedDigit()
    }

    private func metric(_ label: String, _ text: String, value: Double, tint: Color = .primary) -> some View {
        LabeledContent(label) {
            Text(text).foregroundStyle(tint).contentTransition(.numericText(value: value))
        }
    }

    private var yearsSection: some View {
        Section {
            ForEach(model.run.metrics.byYear) { year in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(year.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(BacktestFormat.percent(year.annualReturn, digits: 1))
                            .foregroundStyle(TerminalStyle.pnl(year.annualReturn))
                            .contentTransition(.numericText(value: year.annualReturn))
                    }
                    Text(String(format: "夏普 %.2f", year.sharpe) + " · 回撤 " + BacktestFormat.plainPercent(year.maxDrawdown)
                         + " · 胜率 " + BacktestFormat.plainPercent(year.winRate) + " · \(year.trades) 笔")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("平均持有 " + BacktestFormat.hours(year.averageHoldHours)
                         + " · 手续费占比 " + (year.feeShare.map { BacktestFormat.plainPercent($0) } ?? "—"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .monospacedDigit()
                .padding(.vertical, 2)
            }
        } header: {
            Text("分年")
        } footer: {
            Text("年份收益按当年净值变化计算（不足一年的按实际天数折算）；夏普用日收益、按 365 天年化，区间按 Lo (2002) 标准误。")
        }
    }

    // MARK: Trades

    private func tradesSection(focus: @escaping (BacktestTrade) -> Void) -> some View {
        let rows = sort.apply(model.listedTrades)
        return Section {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(BacktestQuickFilter.allCases) { filter in
                        Toggle(filter.rawValue, isOn: Binding(get: { model.quickFilter == filter }, set: { isOn in
                            guard isOn else { return }
                            model.quickFilter = filter
                            // The chip promises the biggest loss first.
                            if filter == .worstLosses { sort = .worst }
                        }))
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .sensoryFeedback(.selection, trigger: model.quickFilter)

            if rows.isEmpty {
                Text("没有符合条件的交易").foregroundStyle(.secondary)
            }
            ForEach(rows) { trade in
                Button { focus(trade) } label: { TerminalBacktestTradeRow(trade: trade, selected: trade.id == model.selectedTradeID) }
                    .foregroundStyle(.primary)
            }
        } header: {
            HStack {
                Text("交易 · \(rows.count) 笔").contentTransition(.numericText(value: Double(rows.count)))
                Spacer()
                filterMenu
            }
        } footer: {
            Text("点一行，K 线跳到那笔交易。只读：所有数据来自量化系统导出的结果，App 不跑回测、不下单、不保存交易所密钥。2026-10-22 起的加密数据在前向封存期，不显示收益、净值和交易盈亏。")
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("排序", selection: $sort) {
                ForEach(TradeSort.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("品种", selection: $model.listSymbol) {
                Text("全部品种").tag(String?.none)
                ForEach(model.run.symbols, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            Picker("方向", selection: $model.listSide) {
                Text("多空").tag(BacktestSide?.none)
                Text("多").tag(BacktestSide?.some(.long))
                Text("空").tag(BacktestSide?.some(.short))
            }
            Picker("平仓原因", selection: $model.listReason) {
                Text("全部原因").tag(String?.none)
                ForEach(model.exitReasons, id: \.self) { Text(BacktestExitReason.title($0)).tag(String?.some($0)) }
            }
        } label: {
            Label("排序与筛选", systemImage: "line.3.horizontal.decrease.circle")
                .labelStyle(.iconOnly)
                .font(.body)
        }
        .textCase(nil)
    }
}

/// How the trade list is ordered.
private enum TradeSort: String, CaseIterable, Identifiable {
    case newest = "开仓时间（新到旧）"
    case oldest = "开仓时间（旧到新）"
    case worst = "净收益（低到高）"
    case best = "净收益（高到低）"
    case longest = "持有（长到短）"
    var id: String { rawValue }

    func apply(_ trades: [BacktestTrade]) -> [BacktestTrade] {
        switch self {
        case .newest: trades.sorted { $0.entryT > $1.entryT }
        case .oldest: trades.sorted { $0.entryT < $1.entryT }
        case .worst: trades.sorted { $0.pnlNet < $1.pnlNet }
        case .best: trades.sorted { $0.pnlNet > $1.pnlNet }
        case .longest: trades.sorted { $0.holdH > $1.holdH }
        }
    }
}

private struct TerminalBacktestTradeRow: View {
    let trade: BacktestTrade
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(trade.symbol).font(.subheadline.weight(.semibold))
                    Text(trade.side.title).font(.caption.weight(.semibold))
                        .foregroundStyle(trade.side == .long ? .green : .red)
                    Text(trade.exitTitle).font(.caption).foregroundStyle(.secondary)
                }
                // yyyy-MM-dd HH:mm (UTC, as the footer and the sheet say) so both captions fit on one line.
                Text(String(BacktestFormat.time(trade.entryT).prefix(16)) + " · " + BacktestFormat.hours(trade.holdH))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(BacktestFormat.percent(trade.pnlNet, digits: 3)).font(.subheadline.weight(.medium))
                    .foregroundStyle(TerminalStyle.pnl(trade.pnlNet))
                Text("浮盈 " + BacktestFormat.percent(trade.reportedMfe, digits: 2) + " · 浮亏 " + BacktestFormat.percent(trade.reportedMae, digits: 2))
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            if selected {
                Image(systemName: "scope").foregroundStyle(.blue).accessibilityLabel("K 线上正在看")
            }
        }
        .monospacedDigit()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Trade detail

/// One trade: result, entry / exit, costs, signals at entry, how the stop and target moved and how the size changed.
struct TerminalBacktestTradeSheet: View {
    let trade: BacktestTrade
    /// Bars of the trade's symbol (a timeframe fine enough to cover the trade), for the small path chart.
    let bars: [BacktestBar]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PortSightList {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(BacktestFormat.percent(trade.pnlNet, digits: 3))
                            .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(TerminalStyle.pnl(trade.pnlNet))
                            .contentTransition(.numericText(value: trade.pnlNet))
                        Text("净收益（占净值）· " + trade.exitTitle).font(.subheadline).foregroundStyle(.secondary)
                        Text("价格变动 " + BacktestFormat.percent(trade.priceReturn)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 8, trailing: 4))
                }

                if !tradeBars.isEmpty {
                    Section {
                        pathChart.frame(height: 180).padding(.vertical, 6)
                    } header: {
                        Text("价格与止损")
                    } footer: {
                        Text("红色虚线是止损，绿色虚线是止盈，蓝色是仓位。")
                    }
                }

                Section {
                    LabeledContent("开仓", value: trade.entryPriceText + " · " + BacktestFormat.time(trade.entryT))
                    LabeledContent("平仓", value: trade.exitPriceText + " · " + BacktestFormat.time(trade.exitT))
                    LabeledContent("持有", value: BacktestFormat.hours(trade.holdH))
                    LabeledContent("毛收益", value: BacktestFormat.percent(trade.reportedPnlGross, digits: 3))
                    LabeledContent("手续费", value: BacktestFormat.percent(trade.reportedFee.map { -$0 }, digits: 3))
                    LabeledContent("资金费", value: BacktestFormat.percent(trade.reportedFunding, digits: 3))
                    LabeledContent("最大浮盈", value: BacktestFormat.percent(trade.reportedMfe, digits: 3))
                    LabeledContent("最大浮亏", value: BacktestFormat.percent(trade.reportedMae, digits: 3))
                }
                .monospacedDigit()

                if !trade.signalsAtEntry.isEmpty {
                    Section("开仓时信号") {
                        ForEach(trade.signalsAtEntry.keys.sorted(), id: \.self) { key in
                            LabeledContent {
                                Text(String(format: "%.4f", trade.signalsAtEntry[key] ?? 0)).monospacedDigit()
                            } label: {
                                Text(key).monospaced()
                            }
                        }
                    }
                }

                if !trade.stops.isEmpty {
                    Section("止损移动") {
                        levelRows(trade.stops)
                    }
                }
                if !trade.targets.isEmpty {
                    Section("止盈") {
                        levelRows(trade.targets)
                    }
                }

                if !trade.sizePath.isEmpty {
                    Section("仓位变化") {
                        ForEach(Array(trade.sizePath.sorted { $0.t < $1.t }.enumerated()), id: \.offset) { _, step in
                            LabeledContent {
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(BacktestFormat.plainPercent(abs(step.w)))
                                    Text(BacktestFormat.time(step.t)).font(.caption).foregroundStyle(.secondary)
                                }
                                .monospacedDigit()
                            } label: {
                                Text(step.title)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(trade.symbol + " · " + trade.side.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(trade.symbol + " · " + trade.side.title).font(.headline)
                        Text(trade.id).font(.caption2).foregroundStyle(.secondary).monospaced()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }

    private func levelRows(_ levels: [BacktestLevel]) -> some View {
        ForEach(Array(levels.sorted { $0.t < $1.t }.enumerated()), id: \.offset) { index, level in
            LabeledContent {
                Text(BacktestFormat.price(level.px)).monospacedDigit()
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(index == 0 ? "初始" : "第 \(index) 次移动")
                    Text(BacktestFormat.time(level.t)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }

    /// Bars from a little before entry to a little after exit (at least three bars either side), at most about 160.
    private var tradeBars: [BacktestBar] {
        guard !bars.isEmpty else { return [] }
        let barSpan = bars.count > 1 ? bars[1].t - bars[0].t : 0
        let margin = max(max(trade.exitT - trade.entryT, 1) * 0.25, 3 * barSpan)
        let from = trade.entryT - margin, to = trade.exitT + margin
        let inside = bars.filter { $0.t >= from && $0.t <= to }
        guard inside.count > 160 else { return inside }
        let stride = Int((Double(inside.count) / 160).rounded(.up))
        return Swift.stride(from: 0, to: inside.count, by: stride).map { inside[$0] }
    }

    private var pathChart: some View {
        let shown = tradeBars
        let stops = BacktestTrade.stairPoints(trade.steps(trade.stops))
        let targets = BacktestTrade.stairPoints(trade.steps(trade.targets))
        let prices = (shown.flatMap { [$0.l, $0.h] } + stops.map(\.px) + targets.map(\.px) + [trade.entryPx, trade.exitPx]).filter(\.isFinite)
        let low = prices.min() ?? 0, high = prices.max() ?? 1
        let pad = max((high - low) * 0.08, high * 0.002)
        let bottom = low - pad
        let unit = (high - low + 2 * pad) * 0.25 / max(trade.peakWeight, 0.0001)
        return Chart {
            ForEach(trade.sizeSteps.indices, id: \.self) { index in
                let step = trade.sizeSteps[index]
                RectangleMark(xStart: .value("开始", Date(milliseconds: step.from)), xEnd: .value("结束", Date(milliseconds: step.to)),
                              yStart: .value("仓位", bottom), yEnd: .value("仓位", bottom + abs(step.w) * unit))
                    .foregroundStyle(Color.blue.opacity(0.18))
            }
            ForEach(shown, id: \.t) { bar in
                LineMark(x: .value("时间", bar.date), y: .value("收盘", bar.c), series: .value("线", "close"))
                    .foregroundStyle(.primary.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1.2))
            }
            ForEach(Array(stops.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("时间", Date(milliseconds: point.t)), y: .value("止损", point.px), series: .value("线", "stop"))
                    .foregroundStyle(.red).lineStyle(StrokeStyle(lineWidth: 1.4, dash: [3, 2]))
            }
            ForEach(Array(targets.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("时间", Date(milliseconds: point.t)), y: .value("止盈", point.px), series: .value("线", "target"))
                    .foregroundStyle(.green).lineStyle(StrokeStyle(lineWidth: 1.4, dash: [3, 2]))
            }
            if trade.entryPx.isFinite {
                PointMark(x: .value("时间", trade.entryDate), y: .value("开仓价", trade.entryPx))
                    .symbol(.circle).symbolSize(36).foregroundStyle(trade.side == .long ? .green : .red)
            }
            if trade.exitPx.isFinite {
                PointMark(x: .value("时间", trade.exitDate), y: .value("平仓价", trade.exitPx))
                    .symbol(.diamond).symbolSize(36).foregroundStyle(TerminalStyle.pnl(trade.pnlNet))
            }
        }
        .chartYScale(domain: bottom...(high + pad))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: BacktestAxisFormat.hour)
            }
        }
        .environment(\.timeZone, BacktestAxisFormat.utc)
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) }
    }
}
