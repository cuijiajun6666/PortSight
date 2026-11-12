//
//  TerminalBacktestChart.swift
//  PortSight
//
//  Charts for 交易 · 回测 on iPhone: the K-line with one TradingView-style box per trade, and the equity /
//  drawdown chart. Box geometry comes from PortSightKit (BacktestTrade.boxLevels), so it matches the Mac.
//  Drag sideways to pan, pinch to zoom, tap a box for its details, tap elsewhere for a bar's prices.
//

import SwiftUI
import UIKit
import Charts
import PortSightKit

/// Axis labels for the 回测 charts, in UTC like every other time on the page (BacktestFormat.time).
enum BacktestAxisFormat {
    static let utc = TimeZone(identifier: "UTC") ?? .gmt
    static var hour: Date.FormatStyle { Date.FormatStyle(timeZone: utc).month().day().hour() }
    static var month: Date.FormatStyle { Date.FormatStyle(timeZone: utc).year().month() }
}

struct TerminalBacktestPriceChart: View {
    @Bindable var model: BacktestViewerModel
    /// Called when a trade box is tapped.
    var open: (BacktestTrade) -> Void

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
        let trades = model.trades(in: model.run)
        let yDomain = model.priceDomain(bars)
        // Zoomed out with many trades, only the rectangles are drawn; lines, arrows and labels come back closer in.
        let detailed = trades.count <= 60

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
                if let pointer {
                    RuleMark(x: .value("时间", Date(milliseconds: pointer.t + candle / 2)))
                        .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 0.6, dash: [4, 3]))
                    RuleMark(y: .value("价格", pointer.price))
                        .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 0.6, dash: [4, 3]))
                        .annotation(position: .trailing, alignment: .center, spacing: 2) {
                            Text(BacktestFormat.price(pointer.price)).font(.caption2.weight(.medium)).monospacedDigit()
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
                    AxisValueLabel(format: model.span > 120 * 86_400_000 ? BacktestAxisFormat.month : BacktestAxisFormat.hour)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.primary.opacity(0.06))
                    AxisValueLabel()
                }
            }
            .chartPlotStyle { $0.clipped() }
            // Ticks fall on UTC hours / days, matching the UTC labels and readout.
            .environment(\.timeZone, BacktestAxisFormat.utc)
            .chartOverlay { proxy in interactionLayer(proxy, bars: bars, trades: trades) }
            .onChange(of: model.symbol) { pointer = nil }
            .onChange(of: model.timeframe) { pointer = nil }
            .onChange(of: model.runID) { pointer = nil }
        }
    }

    // MARK: Readout

    /// Open / high / low / close of the tapped bar (or the last visible one).
    @ViewBuilder
    private func readout(_ bars: [BacktestBar]) -> some View {
        let bar = pointer.flatMap { point in bars.last { $0.t <= point.t } } ?? bars.last
        if let bar {
            let change = bar.o > 0 ? bar.c / bar.o - 1 : 0
            VStack(alignment: .leading, spacing: 2) {
                Text(BacktestFormat.time(bar.t)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("开 " + BacktestFormat.price(bar.o))
                    Text("高 " + BacktestFormat.price(bar.h))
                    Text("低 " + BacktestFormat.price(bar.l))
                    Text("收 " + BacktestFormat.price(bar.c))
                    Text(BacktestFormat.percent(change))
                }
                .foregroundStyle(bar.c >= bar.o ? up : down)
                .lineLimit(1).minimumScaleFactor(0.7)
            }
            .font(.caption2).monospacedDigit()
        } else {
            Text("这个周期没有 K 线").font(.caption).foregroundStyle(.secondary)
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
                .annotation(position: trade.side == .long ? .top : .bottom, spacing: 6) {
                    Text(trade.exitTitle + " " + BacktestFormat.percent(trade.pnlNet))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.regularMaterial, in: Capsule())
                        .foregroundStyle(resultTint)
                }
        } else {
            PointMark(x: .value("时间", trade.exitDate), y: .value("平仓价", trade.exitPx))
                .symbol { Circle().fill(resultTint).frame(width: 5, height: 5) }
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
                // Sideways drags pan; vertical drags are left to the page so the chart never traps scrolling.
                .gesture(
                    HorizontalPanGesture(
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
                            // Zoom around the time under the fingers.
                            let fraction = min(max(Double((value.startLocation.x - plot.minX) / max(plot.width, 1)), 0), 1)
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
                        model.selectedTradeID = trade.id
                        open(trade)
                    } else {
                        model.selectedTradeID = nil
                        let index = BacktestViewerModel.index(in: bars, atOrBefore: t)
                        pointer = (bars.indices.contains(index) ? bars[index].t : t, price)
                    }
                }
        }
    }
}

/// A one-finger pan that only starts when the finger moves more sideways than up or down, so the list around
/// the chart keeps scrolling vertically.
private struct HorizontalPanGesture: UIGestureRecognizerRepresentable {
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

// MARK: - Equity and drawdown

/// Net asset value against the benchmark, over drawdown. Tapping a day moves the K-line there; the K-line's
/// window is shaded.
struct TerminalBacktestEquityChart: View {
    let model: BacktestViewerModel
    var jumped: () -> Void

    var body: some View {
        let equity = model.run.equity
        VStack(spacing: 6) {
            Chart {
                ForEach(equity, id: \.t) { point in
                    LineMark(x: .value("日期", point.date), y: .value("净值", point.nav), series: .value("曲线", "nav"))
                        .foregroundStyle(by: .value("曲线", "策略"))
                    if let bench = point.benchNav {
                        LineMark(x: .value("日期", point.date), y: .value("净值", bench), series: .value("曲线", "bench"))
                            .foregroundStyle(by: .value("曲线", "基准"))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
            }
            .chartForegroundStyleScale(domain: ["策略", "基准"], range: [Color.blue, Color.secondary])
            .chartLegend(position: .top, alignment: .leading)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: BacktestAxisFormat.month)
                }
            }
            .environment(\.timeZone, BacktestAxisFormat.utc)
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) }
            .chartOverlay { proxy in
                ZStack {
                    WindowShade(model: model, proxy: proxy)
                    tapLayer(proxy)
                }
            }
            .frame(height: 180)

            Chart(equity, id: \.t) { point in
                AreaMark(x: .value("日期", point.date), y: .value("回撤", point.dd))
                    .foregroundStyle(.red.opacity(0.25))
                LineMark(x: .value("日期", point.date), y: .value("回撤", point.dd))
                    .foregroundStyle(.red.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1))
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel { if let dd = value.as(Double.self) { Text(BacktestFormat.plainPercent(dd, digits: 0)) } }
                }
            }
            .chartOverlay { proxy in tapLayer(proxy) }
            .frame(height: 70)
        }
    }

    private func tapLayer(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            let plot = proxy.plotFrame.map { geometry[$0] } ?? .zero
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onTapGesture { location in
                    if let date: Date = proxy.value(atX: location.x - plot.minX) {
                        model.jump(to: date.milliseconds)
                        jumped()
                    }
                }
        }
    }
}

/// The K-line's current window, shaded on the equity chart. A view of its own so that panning the K-line only
/// redraws this rectangle, not the whole curve.
private struct WindowShade: View {
    let model: BacktestViewerModel
    let proxy: ChartProxy

    var body: some View {
        GeometryReader { geometry in
            if let frame = proxy.plotFrame.map({ geometry[$0] }),
               let x0 = proxy.position(forX: Date(milliseconds: model.window.lowerBound)),
               let x1 = proxy.position(forX: Date(milliseconds: model.window.upperBound)) {
                let left = max(frame.minX + x0, frame.minX), right = min(frame.minX + x1, frame.maxX)
                if right > left {
                    Rectangle().fill(Color.blue.opacity(0.1))
                        .frame(width: right - left, height: frame.height)
                        .position(x: (left + right) / 2, y: frame.midY)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
