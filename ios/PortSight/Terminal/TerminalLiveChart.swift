//
//  TerminalLiveChart.swift
//  PortSight
//
//  The K-line for 交易 · 实时 on iPhone, on PortSightKit's LiveViewerModel: candles, one box per closed trade
//  (BacktestTrade.boxLevels, same as the Mac), and each open position drawn from entry to now with its live
//  profit or loss. The chart follows the newest bar; after a sideways drag, 回到最新 brings it back.
//  Drag sideways to pan, pinch to zoom, tap a box for its details, tap elsewhere for a bar's prices.
//  Times are local, like every other time on the page (LiveFormat).
//

import SwiftUI
import UIKit
import Charts
import PortSightKit

struct TerminalLiveChart: View {
    @Bindable var model: LiveViewerModel
    /// Called with the trade ID when a box (closed trade or open position) is tapped.
    var open: (String) -> Void

    @State private var pointer: (t: Double, price: Double)?
    @State private var panStart: ClosedRange<Double>?
    @State private var pinchStart: ClosedRange<Double>?
    @State private var plotWidth: CGFloat = 1

    private let up = Color.green
    private let down = Color.red

    var body: some View {
        // About one drawn candle per 3.5 points of width; zoomed out, neighbouring candles are merged.
        let bars = model.visibleBars(limit: min(320, max(80, Int(plotWidth / 3.5))))
        let candle = model.candleSpan(bars)
        let trades = model.chartTrades
        let positions = model.openPositions
        let yDomain = priceDomain(bars, positions: positions)
        // Zoomed out with many trades, only the rectangles are drawn; lines, arrows and labels come back closer in.
        let detailed = trades.count + positions.count <= 60

        VStack(alignment: .leading, spacing: 6) {
            readout(bars)
            Chart {
                candles(bars, candle: candle)
                ForEach(trades) { trade in
                    let selected = trade.id == model.selectedTradeID
                    if detailed || selected {
                        tradeBox(trade, yDomain: yDomain, labeled: trades.count <= 8 || selected)
                    } else {
                        tradeRectangle(trade, selected: false)
                    }
                }
                ForEach(positions) { position in openPosition(position, yDomain: yDomain) }
                if let pointer {
                    RuleMark(x: .value("时间", Date(milliseconds: pointer.t + candle / 2)))
                        .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 0.6, dash: [4, 3]))
                    RuleMark(y: .value("价格", pointer.price))
                        .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 0.6, dash: [4, 3]))
                        .annotation(position: .trailing, alignment: .center, spacing: 2) {
                            Text(LiveFormat.price(pointer.price)).font(.caption2.weight(.medium)).monospacedDigit()
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3))
                        }
                }
            }
            .chartXScale(domain: Date(milliseconds: model.window.lowerBound)...Date(milliseconds: model.window.upperBound))
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.primary.opacity(0.06))
                    AxisValueLabel(format: axisFormat)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.primary.opacity(0.06))
                    AxisValueLabel()
                }
            }
            .chartPlotStyle { $0.clipped() }
            .chartOverlay { proxy in interactionLayer(proxy, bars: bars, trades: trades + positions.map(\.trade)) }
            .overlay(alignment: .topLeading) {
                if model.followsLatestState == false {
                    Button { withAnimation(.smooth) { model.goToLatest() } } label: {
                        Label("回到最新", systemImage: "arrow.right.to.line")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .padding(6)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.smooth(duration: 0.2), value: model.followsLatestState)
            .onChange(of: model.symbol) { pointer = nil }
            .onChange(of: model.timeframe) { pointer = nil }
            .onChange(of: model.accountKind) { pointer = nil }
        }
    }

    /// Price axis for the visible bars, widened to the selected trade's levels and each open position's entry and
    /// mark. Unlike the Mac (LiveViewerModel.priceDomain), unselected positions' far stops and targets are left out,
    /// so a distant target never squashes the candles on a 320-point chart; those boxes are clipped instead.
    private func priceDomain(_ bars: [BacktestBar], positions: [TradeChartOpenPosition]) -> ClosedRange<Double> {
        var levels: [Double] = []
        if let trade = model.selectedTrade, trade.symbol == model.symbol {
            levels = [trade.entryPx, trade.exitPx] + trade.stops.map(\.px) + trade.targets.map(\.px)
        }
        for position in positions where position.trade.entryT <= model.window.upperBound {
            levels += [position.trade.entryPx, position.trade.exitPx]
        }
        return TradeChartMath.priceDomain(bars, including: levels)
    }

    /// Clock times on short spans (minute timeframes), dates and hours further out.
    private var axisFormat: Date.FormatStyle {
        model.span < 2 * 86_400_000 ? .dateTime.hour().minute() : .dateTime.month().day().hour()
    }

    // MARK: Readout

    /// Open / high / low / close of the tapped bar (or the newest visible one).
    @ViewBuilder
    private func readout(_ bars: [BacktestBar]) -> some View {
        let bar = pointer.flatMap { point in bars.last { $0.t <= point.t } } ?? bars.last
        if let bar {
            let change = bar.o > 0 ? bar.c / bar.o - 1 : 0
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.symbol + " · " + model.timeframe.shortTitle)
                    Text(LiveFormat.time(bar.t))
                }
                .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("开 " + LiveFormat.price(bar.o))
                    Text("高 " + LiveFormat.price(bar.h))
                    Text("低 " + LiveFormat.price(bar.l))
                    Text("收 " + LiveFormat.price(bar.c)).contentTransition(.numericText(value: bar.c))
                    Text(BacktestFormat.percent(change))
                }
                .foregroundStyle(bar.c >= bar.o ? up : down)
                .lineLimit(1).minimumScaleFactor(0.7)
            }
            .font(.caption2).monospacedDigit()
            .animation(.smooth(duration: 0.3), value: bar.c)
        } else {
            Text("这个周期还没有 K 线").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Marks

    @ChartContentBuilder
    private func candles(_ bars: [BacktestBar], candle: Double) -> some ChartContent {
        ForEach(bars, id: \.t) { bar in
            let color = bar.c >= bar.o ? up : down
            RuleMark(x: .value("时间", Date(milliseconds: bar.t + candle / 2)),
                     yStart: .value("低", bar.l), yEnd: .value("高", bar.h))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(color.opacity(0.85))
            RectangleMark(xStart: .value("开始", Date(milliseconds: bar.t + candle * 0.15)),
                          xEnd: .value("结束", Date(milliseconds: bar.t + candle * 0.85)),
                          yStart: .value("开", bar.o),
                          yEnd: .value("收", bar.c == bar.o ? bar.o * 1.0001 : bar.c))
                .foregroundStyle(color)
        }
    }

    /// `labeled`: the exit's reason and result are written only when few trades are on screen, or for the selected one.
    @ChartContentBuilder
    private func tradeBox(_ trade: BacktestTrade, yDomain: ClosedRange<Double>, labeled: Bool) -> some ChartContent {
        let selected = trade.id == model.selectedTradeID
        let levels = BacktestTrade.boxLevels(trade)
        let resultTint = trade.isWin ? up : down

        tradeRectangle(trade, selected: selected)
        // Entry price across the box, and a dashed path from entry to exit in the result's colour.
        LineMark(x: .value("时间", trade.entryDate), y: .value("开仓价", trade.entryPx), series: .value("线", "en-" + trade.id))
            .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1))
        LineMark(x: .value("时间", trade.exitDate), y: .value("开仓价", trade.entryPx), series: .value("线", "en-" + trade.id))
            .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1))
        LineMark(x: .value("时间", trade.entryDate), y: .value("价格", trade.entryPx), series: .value("线", "px-" + trade.id))
            .foregroundStyle(resultTint).lineStyle(StrokeStyle(lineWidth: selected ? 1.6 : 1, dash: [4, 3]))
        LineMark(x: .value("时间", trade.exitDate), y: .value("价格", trade.exitPx), series: .value("线", "px-" + trade.id))
            .foregroundStyle(resultTint).lineStyle(StrokeStyle(lineWidth: selected ? 1.6 : 1, dash: [4, 3]))

        // The selected trade also shows how its stop and target moved, and its size.
        if selected {
            ForEach(Array(BacktestTrade.stairPoints(trade.steps(trade.targets)).enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("时间", Date(milliseconds: point.t)), y: .value("止盈线", point.px), series: .value("线", "tp-" + trade.id))
                    .foregroundStyle(up).lineStyle(StrokeStyle(lineWidth: 1.4, dash: [2, 2]))
            }
            ForEach(Array(BacktestTrade.stairPoints(trade.steps(trade.stops)).enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("时间", Date(milliseconds: point.t)), y: .value("止损线", point.px), series: .value("线", "sl-" + trade.id))
                    .foregroundStyle(down).lineStyle(StrokeStyle(lineWidth: 1.4, dash: [2, 2]))
            }
            let bottom = ([trade.entryPx, trade.exitPx, levels.profit, levels.loss].compactMap { $0 }
                          + trade.stops.map(\.px) + trade.targets.map(\.px)).min() ?? trade.entryPx
            let unit = (yDomain.upperBound - yDomain.lowerBound) * 0.03 / 0.08
            let gap = (yDomain.upperBound - yDomain.lowerBound) * 0.012
            ForEach(Array(trade.sizeSteps.enumerated()), id: \.offset) { _, step in
                // Grows up from the band's bottom edge (taller = bigger): a cut in the size is a notch from the top.
                let base = bottom - gap - max(trade.peakWeight, 0.0001) * unit
                RectangleMark(xStart: .value("开始", Date(milliseconds: step.from)), xEnd: .value("结束", Date(milliseconds: step.to)),
                              yStart: .value("仓位", base), yEnd: .value("仓位", base + abs(step.w) * unit))
                    .foregroundStyle(Color.blue.opacity(0.55))
            }
        }

        // Entry and exit markers; the exit carries its reason when there is room.
        PointMark(x: .value("时间", trade.entryDate), y: .value("开仓价", trade.entryPx))
            .symbol {
                Image(systemName: trade.side == .long ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 9)).foregroundStyle(trade.side == .long ? up : down)
                    .offset(y: trade.side == .long ? 8 : -8)
            }
        if labeled {
            PointMark(x: .value("时间", trade.exitDate), y: .value("平仓价", trade.exitPx))
                .symbol { Circle().fill(resultTint).frame(width: 6, height: 6) }
                .annotation(position: trade.side == .long ? .top : .bottom, spacing: 6,
                            overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                    ChartLabel(text: trade.exitTitle + " " + BacktestFormat.percent(trade.pnlNet), tint: resultTint)
                }
        } else {
            PointMark(x: .value("时间", trade.exitDate), y: .value("平仓价", trade.exitPx))
                .symbol { Circle().fill(resultTint).frame(width: 5, height: 5) }
        }
    }

    /// An open position: the trade box from entry to now, the mark price dot and its live profit or loss. The label
    /// sits above and to the left of the dot so it stays inside the narrow phone plot.
    @ChartContentBuilder
    private func openPosition(_ position: TradeChartOpenPosition, yDomain: ClosedRange<Double>) -> some ChartContent {
        let trade = position.trade
        let tint = position.pnl >= 0 ? up : down
        tradeBox(trade, yDomain: yDomain, labeled: false)
        PointMark(x: .value("时间", trade.exitDate), y: .value("标记价", trade.exitPx))
            .symbol { Circle().fill(tint).frame(width: 7, height: 7) }
            .annotation(position: .top, alignment: .trailing, spacing: 6,
                        overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                ChartLabel(text: LiveFormat.signedMoney(position.pnl) + " · " + BacktestFormat.percent(position.pct, digits: 1),
                           tint: tint, value: position.pnl)
            }
    }

    /// One rectangle per trade, from entry to exit: green profit part above, red loss part below the entry price.
    @ChartContentBuilder
    private func tradeRectangle(_ trade: BacktestTrade, selected: Bool) -> some ChartContent {
        let zone = selected ? 0.32 : 0.18
        let levels = BacktestTrade.boxLevels(trade)
        if let profit = levels.profit {
            RectangleMark(xStart: .value("开始", trade.entryDate), xEnd: .value("结束", trade.exitDate),
                          yStart: .value("开仓价", trade.entryPx), yEnd: .value("止盈", profit))
                .foregroundStyle(up.opacity(zone))
        }
        if let loss = levels.loss {
            RectangleMark(xStart: .value("开始", trade.entryDate), xEnd: .value("结束", trade.exitDate),
                          yStart: .value("开仓价", trade.entryPx), yEnd: .value("止损", loss))
                .foregroundStyle(down.opacity(zone))
        }
    }

    // MARK: Interaction

    private func interactionLayer(_ proxy: ChartProxy, bars: [BacktestBar], trades: [BacktestTrade]) -> some View {
        GeometryReader { geometry in
            let plot = proxy.plotFrame.map { geometry[$0] } ?? .zero
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onAppear { plotWidth = max(plot.width, 1) }
                .onChange(of: plot.width) { _, width in plotWidth = max(width, 1) }
                // Sideways drags pan (and stop following the newest bar); vertical drags are left to the page.
                .gesture(
                    LiveHorizontalPanGesture(
                        began: { panStart = model.window },
                        changed: { dx in
                            guard let start = panStart else { return }
                            let width = start.upperBound - start.lowerBound
                            let shift = -Double(dx / max(plot.width, 1)) * width
                            model.setWindow(center: (start.lowerBound + start.upperBound) / 2 + shift, width: width)
                        },
                        ended: { panStart = nil })
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            if pinchStart == nil { pinchStart = model.window }
                            guard let start = pinchStart else { return }
                            let startWidth = start.upperBound - start.lowerBound
                            let width = startWidth / max(value.magnification, 0.05)
                            // While following, zoom around the newest bar so the chart keeps following;
                            // otherwise around the time under the fingers.
                            let fraction = model.followsLatestState == true
                                ? 1
                                : min(max(Double((value.startLocation.x - plot.minX) / max(plot.width, 1)), 0), 1)
                            let anchor = start.lowerBound + fraction * startWidth
                            let low = anchor - fraction * width
                            model.setWindow(center: low + width / 2, width: width)
                        }
                        .onEnded { _ in pinchStart = nil }
                )
                .onTapGesture { location in
                    let x = location.x - plot.minX, y = location.y - plot.minY
                    guard let date: Date = proxy.value(atX: x), let price: Double = proxy.value(atY: y) else { return }
                    let t = date.milliseconds
                    if let trade = model.trade(at: t, price: price, in: trades) {
                        pointer = nil
                        // Moves the window when part of the trade is off screen, so all of it shows.
                        model.select(trade)
                        open(trade.id)
                    } else {
                        model.selectedTradeID = nil
                        let index = BacktestViewerModel.index(in: bars, atOrBefore: t)
                        pointer = (bars.indices.contains(index) ? bars[index].t : t, price)
                    }
                }
        }
    }
}

/// A result label on the chart. A solid capsule, not a material: materials inside the clipped plot can render as
/// a black bar when a label sits at the plot's edge.
private struct ChartLabel: View {
    let text: String
    let tint: Color
    var value: Double? = nil

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold)).monospacedDigit()
            .contentTransition(.numericText(value: value ?? 0))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.92), in: Capsule())
            .overlay { Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5) }
            .foregroundStyle(tint)
            .animation(.smooth(duration: 0.3), value: value)
    }
}

/// A one-finger pan that only starts when the finger moves more sideways than up or down, so the list around
/// the chart keeps scrolling vertically.
private struct LiveHorizontalPanGesture: UIGestureRecognizerRepresentable {
    var began: () -> Void
    var changed: (CGFloat) -> Void
    var ended: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began: began()
        case .changed: changed(recognizer.translation(in: recognizer.view).x)
        case .ended, .cancelled, .failed: ended()
        default: break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}

// MARK: - A trade's path

/// Close price from a little before entry to exit (or now), with the stop and target steps, entry / exit dots and
/// size blocks. For the 实时 detail sheet.
struct TerminalLivePathChart: View {
    let trade: BacktestTrade
    let bars: [BacktestBar]
    /// For an open position the last point is the mark price now.
    var isOpen = false

    /// Bars from a little before entry to a little after exit (at least three bars either side), at most about 160.
    private var visibleBars: [BacktestBar] {
        guard !bars.isEmpty else { return [] }
        let barSpan = bars.count > 1 ? bars[1].t - bars[0].t : 0
        let margin = max(max(trade.exitT - trade.entryT, 1) * 0.25, 3 * barSpan)
        let from = trade.entryT - margin, to = isOpen ? trade.exitT : trade.exitT + margin
        let inside = bars.filter { $0.t >= from && $0.t <= to }
        guard inside.count > 160 else { return inside }
        let stride = Int((Double(inside.count) / 160).rounded(.up))
        return Swift.stride(from: 0, to: inside.count, by: stride).map { inside[$0] }
    }

    var body: some View {
        let shown = visibleBars
        let stops = BacktestTrade.stairPoints(trade.steps(trade.stops))
        // The target line ends where half the position was taken at the target (if it was): marked with a dot there.
        let targets = BacktestTrade.stairPoints(trade.steps(trade.targets))
        let prices = shown.flatMap { [$0.l, $0.h] } + stops.map(\.px) + targets.map(\.px) + [trade.entryPx, trade.exitPx]
        let low = prices.min() ?? trade.entryPx, high = prices.max() ?? trade.entryPx
        let pad = max((high - low) * 0.08, high * 0.002)
        let bottom = low - pad
        let unit = (high - low + 2 * pad) * 0.25 / max(trade.peakWeight, 0.0001)
        let span = (shown.last?.t ?? trade.exitT) - (shown.first?.t ?? trade.entryT)
        Chart {
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
            // Half the position taken at the target before the exit: the target line ends on this dot.
            if let half = trade.halfTakeProfitT, half < trade.exitT, let last = targets.last {
                PointMark(x: .value("时间", Date(milliseconds: last.t)), y: .value("止盈", last.px))
                    .symbol(.circle).symbolSize(30).foregroundStyle(.green)
            }
            RuleMark(y: .value("开仓价", trade.entryPx))
                .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
            PointMark(x: .value("时间", trade.entryDate), y: .value("开仓价", trade.entryPx))
                .symbol(.circle).symbolSize(36).foregroundStyle(trade.side == .long ? .green : .red)
            PointMark(x: .value("时间", trade.exitDate), y: .value(isOpen ? "标记价" : "平仓价", trade.exitPx))
                .symbol(isOpen ? .circle : .diamond).symbolSize(36)
                .foregroundStyle(TerminalStyle.pnl(trade.side.sign * (trade.exitPx - trade.entryPx)))
        }
        .chartYScale(domain: bottom...(high + pad))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: span < 86_400_000 ? .dateTime.hour().minute() : .dateTime.month().day().hour())
            }
        }
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) }
    }
}
