import SwiftUI
import Charts
import AppKit
import PortSightKit

/// The 回测 page's chart: the shared trade chart on a backtest run.
typealias BacktestPriceChart = TradeChart<BacktestViewerModel>

/// The K-line chart with a TradingView-style long / short position rectangle for every trade, from entry to exit:
/// the entry price splits a green profit part from a red loss part, and a dashed line runs from entry to exit.
/// The selected trade also shows its moving stop / target, its position size and its size changes.
/// Drag to pan, pinch or scroll to zoom, hover for OHLC, click a box for its details.
///
/// The same chart draws a finished backtest (BacktestViewerModel) and an account trading now (LiveViewerModel):
/// open positions get the same box from entry to now with their live profit, and a live chart follows the newest
/// bar until the user pans away (then 回到最新 brings it back).
struct TradeChart<Model: TradeChartModel>: View {
    @Bindable var model: Model
    /// Hover lives in its own object: only the crosshair and the readout read it, so moving the mouse never
    /// re-renders the candles and trade boxes.
    @State private var pointer = BacktestPointer()
    @State private var dragStart: ClosedRange<Double>?
    @State private var pinchStart: ClosedRange<Double>?
    @State private var wheelMonitor: Any?
    @State private var plotWidth: CGFloat = 1

    private let up = DesktopTheme.green
    private let down = Color.red
    private let compareTint = Color.purple

    var body: some View {
        // About one drawn candle per 3.5 points of width; zoomed out, neighbouring candles are merged.
        let bars = model.visibleBars(limit: min(320, max(120, Int(plotWidth / 3.5))))
        let candle = model.candleSpan(bars)
        let trades = model.chartTrades
        let compared = model.comparedTrades
        let open = model.openPositions
        let yDomain = model.priceDomain(bars)
        // Zoomed out with many trades, only the rectangles are drawn; lines, arrows and labels come back closer in.
        let detailed = trades.count + open.count <= 60

        Chart {
            candles(bars, candle: candle)
            ForEach(compared) { trade in comparedTrade(trade, detailed: detailed) }
            ForEach(trades) { trade in
                let selected = trade.id == model.selectedTradeID
                if detailed || selected {
                    tradeBox(trade, yDomain: yDomain, labeled: trades.count <= 14 || selected)
                } else {
                    tradeRectangle(trade, selected: false)
                }
            }
            ForEach(open) { position in openPosition(position, yDomain: yDomain) }
        }
        .chartXScale(domain: Date(milliseconds: model.window.lowerBound)...Date(milliseconds: model.window.upperBound))
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 8)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.primary.opacity(0.06))
                AxisValueLabel(format: axisFormat)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 7)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.primary.opacity(0.06))
                AxisValueLabel()
            }
        }
        .chartPlotStyle { $0.clipped() }
        .chartOverlay { proxy in
            ZStack {
                interactionLayer(proxy, bars: bars, trades: trades + open.map(\.trade))
                BacktestCrosshair(pointer: pointer, proxy: proxy, candle: candle)
            }
        }
        .overlay(alignment: .topLeading) {
            BacktestReadout(title: model.symbol + " · " + model.timeframe.title, pointer: pointer, bars: bars)
                // Leave the 回到最新 button its corner, so the readout shortens instead of running under it.
                .padding(.trailing, model.followsLatestState == false ? 110 : 0)
        }
        .overlay(alignment: .topTrailing) {
            if model.followsLatestState == false {
                Button { model.goToLatest() } label: { Label("回到最新", systemImage: "arrow.right.to.line") }
                    .buttonStyle(.glass).controlSize(.small)
                    .padding(6)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.2), value: model.followsLatestState)
        .onAppear(perform: installWheelMonitor)
        .onDisappear(perform: removeWheelMonitor)
    }

    private var axisFormat: Date.FormatStyle {
        if model.span > 120 * 86_400_000 { return .dateTime.year().month() }
        // Live charts at minute timeframes show clock times.
        if model.followsLatestState != nil, model.span < 2 * 86_400_000 { return .dateTime.hour().minute() }
        return .dateTime.month().day().hour()
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

    // Box edges, stop / target steps and size steps come from PortSightKit (BacktestTrade extension), so the
    // iOS viewer draws identical boxes.

    /// `labeled`: the exit's reason and result are written only when few trades are on screen, or for the selected one.
    @ChartContentBuilder
    /// `winning` overrides the result colour (an open position uses its unrealized P&L, like its mark label).
    private func tradeBox(_ trade: BacktestTrade, yDomain: ClosedRange<Double>, labeled: Bool,
                          winning: Bool? = nil) -> some ChartContent {
        let selected = trade.id == model.selectedTradeID
        let levels = BacktestTrade.boxLevels(trade)
        let resultTint = (winning ?? trade.isWin) ? up : down

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

        // The selected trade also shows how its stop and target moved, its size and its size changes.
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
                    .foregroundStyle(DesktopTheme.blue.opacity(0.55))
            }
            ForEach(Array(trade.sizePath.dropFirst().enumerated()), id: \.offset) { _, step in
                PointMark(x: .value("时间", Date(milliseconds: step.t)), y: .value("开仓价", trade.entryPx))
                    .symbol {
                        Circle().strokeBorder(DesktopTheme.blue, lineWidth: 1.5)
                            .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                            .frame(width: 7, height: 7)
                    }
            }
        }

        // Entry and exit arrows; the exit carries its reason.
        PointMark(x: .value("时间", trade.entryDate), y: .value("开仓价", trade.entryPx))
            .symbol {
                Image(systemName: trade.side == .long ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 11)).foregroundStyle(trade.side == .long ? up : down)
                    .offset(y: trade.side == .long ? 9 : -9)
            }
        if labeled {
            PointMark(x: .value("时间", trade.exitDate), y: .value("平仓价", trade.exitPx))
                .symbol { Circle().fill(resultTint).frame(width: 6, height: 6) }
                .annotation(position: trade.side == .long ? .top : .bottom, spacing: 8,
                            overflowResolution: Self.keepInPlot) {
                    Text(trade.exitTitle + " " + BacktestFormat.percent(trade.pnlNet))
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.regularMaterial, in: Capsule())
                        .foregroundStyle(resultTint)
                }
        } else {
            PointMark(x: .value("时间", trade.exitDate), y: .value("平仓价", trade.exitPx))
                .symbol { Circle().fill(resultTint).frame(width: 6, height: 6) }
        }
    }

    /// An open position: the trade box from entry to now, the mark price line and its live profit or loss.
    @ChartContentBuilder
    private func openPosition(_ position: TradeChartOpenPosition, yDomain: ClosedRange<Double>) -> some ChartContent {
        let trade = position.trade
        let tint = position.pnl >= 0 ? up : down
        tradeBox(trade, yDomain: yDomain, labeled: false, winning: position.pnl >= 0)
        PointMark(x: .value("时间", trade.exitDate), y: .value("标记价", trade.exitPx))
            .symbol { Circle().fill(tint).frame(width: 7, height: 7) }
            .annotation(position: .trailing, spacing: 6, overflowResolution: Self.keepInPlot) {
                Text(LiveFormat.signedMoney(position.pnl) + " · " + BacktestFormat.percent(position.pct, digits: 1))
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .contentTransition(.numericText(value: position.pnl))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
                    .foregroundStyle(tint)
                    .animation(.smooth(duration: 0.3), value: position.pnl)
            }
    }

    /// A label near the plot's edge (an open position's P&L at the newest bar, an exit by the window's end) slides
    /// inside the plot instead of being cut off, however narrow the chart is.
    private static var keepInPlot: AnnotationOverflowResolution { .init(x: .fit(to: .plot), y: .disabled) }

    /// One rectangle per trade, from entry to exit: green profit part, red loss part.
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

    /// The other run's trades: a plain box from entry to exit price, in purple.
    @ChartContentBuilder
    private func comparedTrade(_ trade: BacktestTrade, detailed: Bool) -> some ChartContent {
        RectangleMark(xStart: .value("开始", trade.entryDate), xEnd: .value("结束", trade.exitDate),
                      yStart: .value("开仓价", trade.entryPx), yEnd: .value("平仓价", trade.exitPx))
            .foregroundStyle(compareTint.opacity(0.16))
        if detailed {
            comparedMarkers(trade)
        }
    }

    @ChartContentBuilder
    private func comparedMarkers(_ trade: BacktestTrade) -> some ChartContent {
        PointMark(x: .value("时间", trade.entryDate), y: .value("开仓价", trade.entryPx))
            .symbol(.circle).symbolSize(28).foregroundStyle(compareTint)
        PointMark(x: .value("时间", trade.exitDate), y: .value("平仓价", trade.exitPx))
            .symbol(.diamond).symbolSize(28).foregroundStyle(compareTint)
    }

    // MARK: Interaction

    private func interactionLayer(_ proxy: ChartProxy, bars: [BacktestBar], trades: [BacktestTrade]) -> some View {
        GeometryReader { geometry in
            let plot = proxy.plotFrame.map { geometry[$0] } ?? .zero
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onAppear { plotWidth = max(plot.width, 1) }
                .onChange(of: plot.width) { _, width in plotWidth = max(width, 1) }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        pointer.isInside = true
                        let x = location.x - plot.minX, y = location.y - plot.minY
                        guard let date: Date = proxy.value(atX: x), let price: Double = proxy.value(atY: y) else { return }
                        let t = date.milliseconds
                        let index = BacktestViewerModel.index(in: bars, atOrBefore: t)
                        let snapped = bars.indices.contains(index) ? bars[index].t : t
                        if pointer.point?.t != snapped || pointer.point?.price != price { pointer.point = (snapped, price) }
                    case .ended:
                        pointer.isInside = false
                        pointer.point = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            if dragStart == nil { dragStart = model.window }
                            guard let start = dragStart else { return }
                            let shift = -Double(value.translation.width / max(plot.width, 1)) * (start.upperBound - start.lowerBound)
                            model.setWindow(center: (start.lowerBound + start.upperBound) / 2 + shift,
                                            width: start.upperBound - start.lowerBound)
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            if pinchStart == nil { pinchStart = model.window }
                            guard let start = pinchStart else { return }
                            let width = (start.upperBound - start.lowerBound) / max(value.magnification, 0.05)
                            model.setWindow(center: (model.window.lowerBound + model.window.upperBound) / 2, width: width)
                        }
                        .onEnded { _ in pinchStart = nil }
                )
                .onTapGesture { location in
                    let x = location.x - plot.minX, y = location.y - plot.minY
                    guard let date: Date = proxy.value(atX: x), let price: Double = proxy.value(atY: y) else { return }
                    model.select(model.trade(at: date.milliseconds, price: price, in: trades))
                }
        }
    }

    /// Two-finger scroll: sideways pans; with ⌘ held, up and down zooms around the pointer's time.
    /// Plain vertical scrolling is left to the page, so the chart never traps it.
    private func installWheelMonitor() {
        guard wheelMonitor == nil else { return }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard pointer.isInside else { return event }
            let dx = Double(event.scrollingDeltaX), dy = Double(event.scrollingDeltaY)
            if event.modifierFlags.contains(.command), dy != 0 {
                model.zoom(by: exp(-dy * (event.hasPreciseScrollingDeltas ? 0.006 : 0.06)), around: pointer.point?.t)
                return nil
            }
            if abs(dx) > abs(dy) {
                model.pan(by: -dx / Double(plotWidth) * model.span)
                return nil
            }
            return event
        }
    }

    private func removeWheelMonitor() {
        if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }
        wheelMonitor = nil
    }
}

/// Where the mouse is over the price chart (snapped bar time and price). Kept apart from the chart's own state.
@Observable
final class BacktestPointer {
    var point: (t: Double, price: Double)?
    var isInside = false
}

/// Dashed crosshair and price tag, drawn over the chart; only this view follows the mouse.
private struct BacktestCrosshair: View {
    let pointer: BacktestPointer
    let proxy: ChartProxy
    let candle: Double

    var body: some View {
        GeometryReader { geometry in
            if let point = pointer.point, let frame = proxy.plotFrame.map({ geometry[$0] }),
               let x = proxy.position(forX: Date(milliseconds: point.t + candle / 2)),
               let y = proxy.position(forY: point.price) {
                let px = frame.minX + x, py = frame.minY + y
                Path { path in
                    path.move(to: CGPoint(x: px, y: frame.minY)); path.addLine(to: CGPoint(x: px, y: frame.maxY))
                    path.move(to: CGPoint(x: frame.minX, y: py)); path.addLine(to: CGPoint(x: frame.maxX, y: py))
                }
                .stroke(.secondary, style: StrokeStyle(lineWidth: 0.6, dash: [4, 3]))
                Text(BacktestFormat.price(point.price)).font(.system(size: 10, weight: .medium)).monospacedDigit()
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.primary.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    .fixedSize()
                    .position(x: frame.maxX + 26, y: py)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Open / high / low / close of the bar under the mouse (or the last bar).
private struct BacktestReadout: View {
    let title: String
    let pointer: BacktestPointer
    let bars: [BacktestBar]
    private let up = DesktopTheme.green
    private let down = Color.red

    var body: some View {
        let bar = pointer.point.flatMap { h in bars.last { $0.t <= h.t } } ?? bars.last
        if let bar {
            // A narrower chart (a trade card beside it) drops the time, then open / high / low, never wrapping.
            ViewThatFits(in: .horizontal) {
                row(bar, time: true, range: true)
                row(bar, time: false, range: true)
                row(bar, time: false, range: false)
            }
            .padding(6)
            .allowsHitTesting(false)
        }
    }

    private func row(_ bar: BacktestBar, time: Bool, range: Bool) -> some View {
        let change = bar.o > 0 ? bar.c / bar.o - 1 : 0
        return HStack(spacing: 10) {
            Text(title).fontWeight(.semibold)
            if time { Text(BacktestFormat.time(bar.t)).foregroundStyle(.secondary) }
            Group {
                if range {
                    Text("开 " + BacktestFormat.price(bar.o))
                    Text("高 " + BacktestFormat.price(bar.h))
                    Text("低 " + BacktestFormat.price(bar.l))
                }
                Text("收 " + BacktestFormat.price(bar.c))
            }
            .foregroundStyle(bar.c >= bar.o ? up : down)
            Text(BacktestFormat.percent(change)).foregroundStyle(change >= 0 ? up : down)
        }
        .lineLimit(1)
        .fixedSize()
        .font(.system(size: 11)).monospacedDigit()
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
    }
}
