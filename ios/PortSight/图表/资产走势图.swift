//
//  资产走势图.swift
//  PortSight
//
//  Created by Chris Cui on 29/4/2026.
//

import SwiftUI
import Charts
import SwiftData
import PortSightKit

/// A deposit or withdrawal marked on the value curve (入金 / 转入 up, 出金 / 转出 down). `date` is the date of the
/// curve point it belongs to (the chart puts it on the nearest point).
struct AssetTrendFlow: Identifiable, Equatable {
    let id: String
    let date: Date
    /// 入金 / 出金 / 转入 / 转出.
    let title: String
    /// In the base currency: in positive, out negative.
    let amount: Double

    var isIn: Bool { amount >= 0 }
}

struct AssetTrendChart: View {
    private enum AssetTrendRange: String, CaseIterable, Identifiable {
        case week = "1W"
        case month = "1M"
        case all = "All"

        var id: String { rawValue }

        var dayCount: Int? {
            switch self {
            case .week:
                return 7
            case .month:
                return 30
            case .all:
                return nil
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let snapshots: [AssetChartSnapshot]
    let principal: Double
    let currentTotalAsset: Double
    let metric: PortfolioTrendMetric
    /// 收益率 as a curve of its own (percentage points, same dates as `snapshots`), e.g. the account's time-weighted
    /// return; nil: 收益率 is worked out from `snapshots` and `principal`.
    let returnSnapshots: [AssetChartSnapshot]?
    /// Deposits and withdrawals to mark on the curve.
    let flows: [AssetTrendFlow]
    /// Every point is drawn (several a day for an intraday curve); otherwise one per New York day.
    let keepsEveryPoint: Bool
    /// The line's colour (up green, down red); nil: the total against the principal.
    let trendUp: Bool?
    let showsRangePicker: Bool
    let onLaunchAnimationFinished: (() -> Void)?

    @State private var domainLength: Double = 1
    @State private var scrollPosition: Double = 0

    
    @State private var isInspecting = false
    @State private var isTouching = false
    @State private var selectedIndex: Int? = nil
    @Binding var selectedAssetValue: Double?
    
    
    @State private var lastHapticIndex: Int? = nil

    private var maxX: Double {
        Double(max(normalizedSnapshots.count - 1, 1))
    }
    
    
    /// The curve's heights (0...1 of the plot), easing to each new curve frame by frame.
    @State private var heights: TrendMorph
    /// The line's colour as a green fraction (1 green, 0 red), easing when the trend flips.
    @State private var greenness: TrendMorph
    /// The deposit / withdrawal markers on the curve now, and those growing in or shrinking away.
    @State private var shownMarkers: [FlowMarker]
    @State private var markerFades = MarkerFades()
    /// A morph, colour change or marker fade is running: the plot is redrawn every frame until `frameDriver` ends it.
    @State private var isAnimatingFrames = false
    @State private var frameDriver: Task<Void, Never>?
    @State private var lineProgress: Double = 0
    @State private var sourceSnapshots: [AssetChartSnapshot]
    @State private var displayedSnapshots: [AssetChartSnapshot]
    @State private var semanticSnapshots: [AssetChartSnapshot]
    @State private var pendingSnapshots: [AssetChartSnapshot]?
    @State private var isLaunchAnimating = false
    @State private var selectedRange: AssetTrendRange = .all
    private static var hasPlayedLineAnimation = false

    init(
        snapshots: [AssetChartSnapshot],
        principal: Double,
        currentTotalAsset: Double,
        selectedAssetValue: Binding<Double?>,
        metric: PortfolioTrendMetric = .amount,
        returnSnapshots: [AssetChartSnapshot]? = nil,
        flows: [AssetTrendFlow] = [],
        keepsEveryPoint: Bool = false,
        trendUp: Bool? = nil,
        showsRangePicker: Bool = false,
        onLaunchAnimationFinished: (() -> Void)? = nil
    ) {
        self.snapshots = snapshots
        self.principal = principal
        self.currentTotalAsset = currentTotalAsset
        self.metric = metric
        self.returnSnapshots = returnSnapshots
        self.flows = flows
        self.keepsEveryPoint = keepsEveryPoint
        self.trendUp = trendUp
        self.showsRangePicker = showsRangePicker
        self.onLaunchAnimationFinished = onLaunchAnimationFinished
        _selectedAssetValue = selectedAssetValue
        let direct = metric == .returnRate && returnSnapshots != nil
        let sortedSnapshots = Self.ordered(direct ? returnSnapshots ?? [] : snapshots, keepsEveryPoint: keepsEveryPoint)
        _sourceSnapshots = State(initialValue: sortedSnapshots)
        _displayedSnapshots = State(initialValue: sortedSnapshots)
        _semanticSnapshots = State(initialValue: sortedSnapshots)
        _heights = State(initialValue: TrendMorph(Self.plotHeights(for: sortedSnapshots, metric: metric, principal: principal,
                                                                   direct: direct)))
        let up = trendUp ?? (currentTotalAsset - principal >= 0)
        _greenness = State(initialValue: TrendMorph([up ? 1 : 0]))
        _shownMarkers = State(initialValue: Self.markers(for: flows, semantic: sortedSnapshots,
                                                         displayCount: sortedSnapshots.count))
    }

    /// The line is green (up) rather than red.
    private var isTrendUp: Bool {
        trendUp ?? (currentTotalAsset - principal >= 0)
    }

    /// Changes whenever the plotted curve does (cheaper than comparing the points as text on every redraw).
    private var plottedInputKey: Int {
        var hasher = Hasher()
        hasher.combine(plottedInput.count)
        for snapshot in plottedInput {
            hasher.combine(snapshot.date)
            hasher.combine(snapshot.value)
        }
        return hasher.finalize()
    }

    /// What is plotted: the return curve in 收益率 when there is one, else the values.
    private var plottedInput: [AssetChartSnapshot] {
        plotsReturnsDirectly ? returnSnapshots ?? [] : snapshots
    }

    /// The plotted values are already percentage points (the return curve), not amounts.
    private var plotsReturnsDirectly: Bool { metric == .returnRate && returnSnapshots != nil }

    /// Sorted by date; one per New York day unless every point is kept.
    private static func ordered(_ snapshots: [AssetChartSnapshot], keepsEveryPoint: Bool) -> [AssetChartSnapshot] {
        keepsEveryPoint ? snapshots.sorted { $0.date < $1.date } : uniqueDailySnapshots(snapshots)
    }

    private func ordered(_ snapshots: [AssetChartSnapshot]) -> [AssetChartSnapshot] {
        Self.ordered(snapshots, keepsEveryPoint: keepsEveryPoint)
    }

    private static func uniqueDailySnapshots(_ snapshots: [AssetChartSnapshot]) -> [AssetChartSnapshot] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current

        let sortedSnapshots = snapshots.sorted { $0.date < $1.date }
        var snapshotsByDay: [Date: AssetChartSnapshot] = [:]

        for snapshot in sortedSnapshots {
            let day = calendar.startOfDay(for: snapshot.date)
            snapshotsByDay[day] = snapshot
        }

        return snapshotsByDay
            .values
            .sorted { $0.date < $1.date }
    }
    
    private func rangeSnapshots(
        from snapshots: [AssetChartSnapshot],
        range: AssetTrendRange
    ) -> [AssetChartSnapshot] {
        let sortedSnapshots = ordered(snapshots)
        guard let dayCount = range.dayCount,
              let latestDate = sortedSnapshots.last?.date else {
            return sortedSnapshots
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let startDate = calendar.date(
            byAdding: .day,
            value: -(dayCount - 1),
            to: latestDate
        ) ?? latestDate

        let filtered = sortedSnapshots.filter { $0.date >= startDate }
        return filtered.isEmpty ? Array(sortedSnapshots.suffix(1)) : filtered
    }

    private var normalizedSnapshots: [AssetChartSnapshot] {
        displayedSnapshots
    }

    var body: some View {
        VStack(spacing: 10) {
            // Redrawn every frame only while something is easing (the curve, its colour, the markers); otherwise
            // the final values are drawn and the timeline is paused.
            TimelineView(.animation(minimumInterval: nil, paused: !isAnimatingFrames)) { context in
                plot(plotFrame(at: isAnimatingFrames ? context.date : .distantFuture))
            }
        .onAppear {
            if sourceSnapshots.isEmpty, !plottedInput.isEmpty {
                sourceSnapshots = ordered(plottedInput)
            }

            if displayedSnapshots.isEmpty, !sourceSnapshots.isEmpty {
                let initialSnapshots = rangeSnapshots(
                    from: sourceSnapshots,
                    range: selectedRange
                )
                displayedSnapshots = initialSnapshots
                semanticSnapshots = initialSnapshots
                snapPlotHeights()
                shownMarkers = currentMarkers
            }

            guard !Self.hasPlayedLineAnimation else {
                lineProgress = 1
                applySnapshotsAfterLaunchIfNeeded(plottedInput)
                onLaunchAnimationFinished?()
                return
            }

            guard !normalizedSnapshots.isEmpty else {
                onLaunchAnimationFinished?()
                return
            }

            playLaunchAnimation()
        }
        // A new curve (another range or scope, new data, or 金额 ↔ 收益率 when 收益率 has a curve of its own).
        .onChange(of: plottedInputKey) { _, _ in
            resetInspection()
            applySnapshotsAfterLaunchIfNeeded(plottedInput)
        }
        .onChange(of: metric) { _, _ in
            resetInspection()
            // With a return curve of its own the new curve arrives through the change above.
            if returnSnapshots == nil { animatePlotHeights() }
        }
        .onChange(of: principal) { _, _ in
            if metric == .returnRate, !plotsReturnsDirectly { animatePlotHeights() }
        }
        // Green ↔ red eases through the colours instead of switching at once.
        .onChange(of: isTrendUp) { _, up in
            animateColour(up: up)
        }
        // New deposits / withdrawals on the same curve.
        .onChange(of: flows) { _, _ in
            refreshMarkers()
        }
        .onDisappear {
            frameDriver?.cancel()
            frameDriver = nil
            finishFrames()
            resetInspection()
        }
        .onChange(of: normalizedSnapshots.count) { _, count in
            fitFullDomain()

            guard count > 0, Self.hasPlayedLineAnimation else { return }
            lineProgress = 1
        }
        // A return worked out from the principal needs one (no division by 0); a return curve of its own does not.
        .opacity(metric == .returnRate && !plotsReturnsDirectly && principal <= 0 ? 0 : 1)
        .overlay {
            if metric == .returnRate && !plotsReturnsDirectly && principal <= 0 {
                Text("暂无收益率数据").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(height: 176) // about 20% lower than the original 220
        .onChange(of: domainLength) { _, newValue in
            if newValue >= maxX {
                scrollPosition = 0
            } else {
                scrollPosition = clampScroll(scrollPosition, length: newValue)
            }

        }
        .onAppear {
            fitFullDomain()
        }
        .overlay(alignment: .bottomTrailing) {
            Text(latestVisibleDateText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                // In the x-axis row, ending where the plot ends (the y-axis labels take the column to its right),
                // rather than stacked under the lowest y-axis label.
                .padding(.trailing, Self.yLabelWidth + Self.yLabelSpacing - 6)
                .offset(y: 2)
        }
            
            if showsRangePicker {
                Picker("资产趋势范围", selection: $selectedRange) {
                    ForEach(AssetTrendRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .padding(.horizontal)
                .onChange(of: selectedRange) { _, _ in
                    selectedIndex = nil
                    selectedAssetValue = nil
                    animateDisplayedSnapshots(
                        to: rangeSnapshots(
                            from: sourceSnapshots,
                            range: selectedRange
                        )
                    )
                }
            }
        }
    }

    /// The y-axis labels' column, the same width for amounts and percentages so the plot never changes width; the
    /// numbers start right after the plot.
    private static let yLabelWidth: CGFloat = 58
    private static let yLabelSpacing: CGFloat = 4

    /// The chart for one frame of the curve.
    private func plot(_ frame: PlotFrame) -> some View {
        Chart {
            chartContent(frame)
        }
        .chartPlotStyle { plotArea in
            plotArea
                .mask(alignment: .leading) {
                    // A little wider than the plot, so a flow marker on the first or last point is not cut in half.
                    Rectangle()
                        .padding(-12)
                        .scaleEffect(x: lineProgress, anchor: .leading)
                }
        }
        .chartXScale(domain: -0.015...maxX + 0.015)
        .chartScrollableAxes([])
        .chartXVisibleDomain(length: domainLength)
        .chartScrollPosition(x: $scrollPosition)
        .chartYScale(domain: 0.0...1.0)
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                AxisValueLabel {
                    if let index = value.as(Int.self),
                       normalizedSnapshots.indices.contains(index) {
                        Text(axisLabel(semanticSnapshot(for: index).date))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: [0.0, 0.25, 0.5, 0.75, 1.0]) { value in
                AxisGridLine()
                AxisValueLabel(horizontalSpacing: Self.yLabelSpacing) {
                    if let height = value.as(Double.self) {
                        let number = visibleYDomain.lowerBound + height * (visibleYDomain.upperBound - visibleYDomain.lowerBound)
                        Group {
                            if metric == .returnRate {
                                Text(number / 100, format: .percent.precision(.fractionLength(0...2)))
                            } else {
                                Text(number, format: .number.precision(.fractionLength(0)))
                            }
                        }
                        // Keep label width identical across units so points never drift sideways; the number starts
                        // right next to the plot.
                        .frame(width: Self.yLabelWidth, alignment: .leading)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plotAnchor = proxy.plotFrame {
                    let plotFrame = geo[plotAnchor]
                    AssetChartTouchSurface { location in
                        isTouching = true
                        isInspecting = true
                        updateSelectedPoint(location: location, plotFrame: plotFrame, proxy: proxy, haptic: true)
                    } onEnd: {
                        resetInspection()
                    }
                    flowMarkerLayer(frame, proxy: proxy, plotFrame: plotFrame)
                }
            }
        }
    }

    @ChartContentBuilder
    private func chartContent(_ frame: PlotFrame) -> some ChartContent {
        baseTrendMarks(frame)
        selectedHighlightMarks(frame)
        maxAnnotationMark(frame)
        selectedPointMarks(frame)
    }

    /// One frame of the curve: its heights, its colour and where its markers are, how big and how visible.
    private struct PlotFrame {
        let heights: [Double]
        let color: Color
        let markers: [PlacedMarker]
        /// The area's lower edge.
        let floor: Double

        func height(_ index: Int) -> Double {
            heights.indices.contains(index) ? heights[index] : 0
        }
    }

    private func plotFrame(at date: Date) -> PlotFrame {
        var values = heights.values(at: date)
        if values.count != displayedSnapshots.count {
            // Not morphing to these points (yet): drawn where they belong.
            values = Self.plotHeights(for: displayedSnapshots, metric: metric, principal: principal,
                                      direct: plotsReturnsDirectly)
        }
        let green = min(max(greenness.values(at: date).first ?? (isTrendUp ? 1 : 0), 0), 1)
        return PlotFrame(heights: values, color: Self.trendColor(green: green),
                         markers: placedMarkers(at: date, count: values.count), floor: values.min() ?? 0)
    }

    /// Red at 0, green at 1, the colours in between on the way.
    private static func trendColor(green: Double) -> Color {
        if green >= 0.999 { return .green }
        if green <= 0.001 { return .red }
        return Color.red.mix(with: .green, by: green, in: .perceptual)
    }

    /// A flow marker: a point (display index) carrying deposits / withdrawals, one per direction. Identified by the
    /// point's date and direction, so the same deposit on another range's curve is the same marker.
    private struct FlowMarker: Identifiable, Equatable {
        let id: String
        let index: Int
        /// The display points it was placed among.
        let count: Int
        let isIn: Bool
    }

    /// A marker as drawn in one frame.
    private struct PlacedMarker: Identifiable {
        let id: String
        let index: Int
        let isIn: Bool
        let scale: Double
        let opacity: Double
    }

    /// Markers growing in (from when) and shrinking away (from when, and where they were).
    private struct MarkerFades {
        static let appearDelay = 0.38
        static let appearDuration = 0.42
        static let leaveDuration = 0.22

        var appearing: [String: Date] = [:]
        var leaving: [String: (marker: FlowMarker, start: Date)] = [:]

        var isEmpty: Bool { appearing.isEmpty && leaving.isEmpty }

        var end: Date {
            let appear = appearing.values.max().map { $0.addingTimeInterval(Self.appearDuration) } ?? .distantPast
            let leave = leaving.values.map(\.start).max().map { $0.addingTimeInterval(Self.leaveDuration) } ?? .distantPast
            return max(appear, leave)
        }
    }

    /// The semantic point each flow belongs to: the nearest in time.
    private static func flowsBySemanticIndex(_ flows: [AssetTrendFlow],
                                             semantic: [AssetChartSnapshot]) -> [Int: [AssetTrendFlow]] {
        guard !flows.isEmpty, !semantic.isEmpty else { return [:] }
        var result: [Int: [AssetTrendFlow]] = [:]
        for flow in flows {
            guard let nearest = semantic.indices.min(by: {
                abs(semantic[$0].date.timeIntervalSince(flow.date)) < abs(semantic[$1].date.timeIntervalSince(flow.date))
            }) else { continue }
            result[nearest, default: []].append(flow)
        }
        return result
    }

    private var flowsBySemanticIndex: [Int: [AssetTrendFlow]] {
        Self.flowsBySemanticIndex(flows, semantic: semanticSnapshots)
    }

    /// The markers of `flows` on a curve of `semantic` points drawn as `displayCount` points.
    private static func markers(for flows: [AssetTrendFlow], semantic: [AssetChartSnapshot],
                                displayCount: Int) -> [FlowMarker] {
        let grouped = flowsBySemanticIndex(flows, semantic: semantic)
        var seen = Set<String>()
        return grouped.keys.sorted().flatMap { index -> [FlowMarker] in
            let display = displayIndex(forSemanticIndex: index, semanticCount: semantic.count, displayCount: displayCount)
            let stamp = semantic[index].date.timeIntervalSince1970
            return (grouped[index] ?? []).map {
                FlowMarker(id: "\(stamp)-\($0.isIn)", index: display, count: displayCount, isIn: $0.isIn)
            }
        }
        .filter { seen.insert($0.id).inserted }
    }

    private var currentMarkers: [FlowMarker] {
        Self.markers(for: flows, semantic: semanticSnapshots, displayCount: displayedSnapshots.count)
    }

    /// The flows at a display index (the scrub readout).
    private func flows(atDisplayIndex index: Int) -> [AssetTrendFlow] {
        guard !flows.isEmpty, !semanticSnapshots.isEmpty else { return [] }
        return flowsBySemanticIndex[semanticIndex(forDisplayIndex: index)] ?? []
    }

    /// The markers in one frame: new ones pop in once the curve has nearly settled, gone ones shrink away where
    /// they were.
    private func placedMarkers(at date: Date, count: Int) -> [PlacedMarker] {
        var placed = shownMarkers.map { marker -> PlacedMarker in
            guard let start = markerFades.appearing[marker.id] else {
                return PlacedMarker(id: marker.id, index: marker.index, isIn: marker.isIn, scale: 1, opacity: 1)
            }
            let progress = min(max(date.timeIntervalSince(start) / MarkerFades.appearDuration, 0), 1)
            return PlacedMarker(id: marker.id, index: marker.index, isIn: marker.isIn,
                                scale: Self.easeOutBack(progress), opacity: min(progress * 2, 1))
        }
        let shownIDs = Set(shownMarkers.map(\.id))
        for (id, fade) in markerFades.leaving where !shownIDs.contains(id) {
            let progress = min(max(date.timeIntervalSince(fade.start) / MarkerFades.leaveDuration, 0), 1)
            guard progress < 1 else { continue }
            // Where it was along the curve, among the points drawn now.
            let index = fade.marker.count > 1 && count > 1
                ? Int((Double(fade.marker.index) / Double(fade.marker.count - 1) * Double(count - 1)).rounded())
                : 0
            let eased = progress * progress
            placed.append(PlacedMarker(id: "leaving-" + id, index: min(max(index, 0), max(count - 1, 0)),
                                       isIn: fade.marker.isIn, scale: 1 - 0.75 * eased, opacity: 1 - eased))
        }
        return placed
    }

    /// 0 → 1 with a little overshoot, for a marker popping in.
    private static func easeOutBack(_ t: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }

    /// 入金 / 转入 as a small up marker, 出金 / 转出 as a down marker, on the curve. Drawn over the plot rather than as
    /// chart symbols: a chart redraws a symbol view from scratch whenever it changes, which stalled the curve while the
    /// markers grew and shrank.
    private func flowMarkerLayer(_ frame: PlotFrame, proxy: ChartProxy, plotFrame: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(frame.markers) { marker in
                if let x = proxy.position(forX: marker.index), let y = proxy.position(forY: frame.height(marker.index)) {
                    FlowMarkerSymbol(isIn: marker.isIn)
                        .scaleEffect(max(marker.scale, 0.01))
                        .opacity(marker.opacity * (selectedIndex == nil || selectedIndex == marker.index ? 1 : 0.45))
                        .position(x: x, y: y)
                }
            }
        }
        .frame(width: plotFrame.width, height: plotFrame.height, alignment: .topLeading)
        // Revealed with the line as it draws itself in, like the plot.
        .mask(alignment: .leading) {
            Rectangle()
                .padding(-12)
                .scaleEffect(x: lineProgress, anchor: .leading)
        }
        .offset(x: plotFrame.minX, y: plotFrame.minY)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
    }

    @ChartContentBuilder
    private func baseTrendMarks(_ frame: PlotFrame) -> some ChartContent {
        ForEach(normalizedSnapshots.indices, id: \.self) { i in
            LineMark(
                x: .value("Day", i),
                y: .value("Height", frame.height(i)),
                series: .value("Series", "base")
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(frame.color.opacity(selectedIndex == nil ? 1.0 : 0.3))

            AreaMark(
                x: .value("Day", i),
                yStart: .value("Min", frame.floor),
                yEnd: .value("Height", frame.height(i))
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    gradient: Gradient(colors: [
                        frame.color.opacity(selectedIndex == nil ? 0.3 : 0.1),
                        .clear
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    @ChartContentBuilder
    private func selectedHighlightMarks(_ frame: PlotFrame) -> some ChartContent {
        if let selectedIndex, selectedIndex > 0 {
            ForEach(0...selectedIndex, id: \.self) { i in
                LineMark(
                    x: .value("Day", i),
                    y: .value("Height", frame.height(i)),
                    series: .value("Series", "highlight")
                )
                .interpolationMethod(selectedIndex < 2 ? .linear : .catmullRom)
                .foregroundStyle(frame.color)
            }
        }
    }

    @ChartContentBuilder
    private func maxAnnotationMark(_ frame: PlotFrame) -> some ChartContent {
        if let max = visibleMax {
            PointMark(
                x: .value("Max", max.index),
                y: .value("Height", frame.height(max.index))
            )
            .symbolSize(0)
            .foregroundStyle(frame.color.opacity(isTouching ? 0 : 1))
            .annotation(
                position: .top,
                alignment: maxAnnotationAlignment(
                    index: max.index,
                    count: normalizedSnapshots.count
                )
            ) {
                Text(metric.annotation(for: max.value))
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .opacity(isInspecting ? 0 : 1)
                    .offset(
                        x: maxAnnotationXOffset(
                            index: max.index,
                            count: normalizedSnapshots.count
                        ),
                        y: isInspecting ? -4 : 0
                    )
                    .animation(.easeInOut(duration: 0.25), value: isInspecting)
                    .padding(.bottom, 7)
            }
        }
    }

    @ChartContentBuilder
    private func selectedPointMarks(_ frame: PlotFrame) -> some ChartContent {
        if let selectedIndex,
           normalizedSnapshots.indices.contains(selectedIndex) {

            let minY = 0.0
            let maxY = 1.0
            let range = maxY - minY

            RuleMark(
                x: .value("Selected Date", selectedIndex),
                yStart: .value("Start", minY + range * 0.1),
                yEnd: .value("End", maxY - range * 0.12)
            )
            .foregroundStyle(.gray.opacity(0.55))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .annotation(position: .top, alignment: .center,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                // The date, and the deposits / withdrawals of that point with their amounts.
                let flowsHere = flows(atDisplayIndex: selectedIndex)
                HStack(spacing: 6) {
                    Text(scrubLabel(semanticSnapshot(for: selectedIndex).date))
                        .foregroundStyle(.secondary)
                    ForEach(Array(flowsHere.enumerated()), id: \.offset) { _, flow in
                        Text(flow.title + " " + terminalSignedMoney(flow.amount))
                            .foregroundStyle(FlowMarkerSymbol.color(isIn: flow.isIn))
                            .monospacedDigit()
                    }
                }
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.trailing, flowsHere.isEmpty ? 35 : 0)
            }

            PointMark(
                x: .value("Selected", selectedIndex),
                y: .value("Height", frame.height(selectedIndex))
            )
            .symbolSize(60)
            .foregroundStyle(frame.color)
        }
    }

    private var visibleMax: (index: Int, value: Double)? {
        guard !semanticSnapshots.isEmpty else { return nil }

        let displayStart = max(0, Int(floor(scrollPosition)))
        let displayEnd = min(
            normalizedSnapshots.count - 1,
            Int(ceil(scrollPosition + domainLength))
        )
        let start = semanticIndex(forDisplayIndex: displayStart)
        let end = semanticIndex(forDisplayIndex: displayEnd)

        guard start <= end else { return nil }

        return semanticSnapshots[start...end]
            .enumerated()
            .compactMap { offset, snapshot -> (index: Int, value: Double)? in
                guard snapshot.isRecorded else { return nil }
                return (displayIndex(forSemanticIndex: start + offset), plotValue(snapshot.value))
            }
            .max {
                if $0.value == $1.value {
                    return $0.index < $1.index
                }
                return $0.value < $1.value
            }
    }

    private func plotValue(_ assetValue: Double) -> Double {
        plotsReturnsDirectly ? assetValue : metric.value(for: assetValue, principal: principal)
    }

    private func resetInspection() {
        isTouching = false
        isInspecting = false
        selectedIndex = nil
        selectedAssetValue = nil
        lastHapticIndex = nil
    }

    private var latestVisibleDateText: String {
        guard !semanticSnapshots.isEmpty else { return "" }

        let visibleEnd = min(
            normalizedSnapshots.count - 1,
            Int(ceil(scrollPosition + domainLength))
        )

        let semanticIndex = semanticIndex(forDisplayIndex: visibleEnd)
        guard semanticSnapshots.indices.contains(semanticIndex) else { return "" }

        return scrubLabel(semanticSnapshots[semanticIndex].date)
    }

    // MARK: Dates

    /// Several points a day (an intraday curve: a point a minute, or every 15 minutes): times are shown.
    private var isSubDaily: Bool {
        guard keepsEveryPoint, semanticSnapshots.count > 2 else { return false }
        let gaps = zip(semanticSnapshots.dropFirst(), semanticSnapshots).map { $0.date.timeIntervalSince($1.date) }.sorted()
        return gaps[gaps.count / 2] < 6 * 3600
    }

    /// The curve covers about one day (times alone are enough).
    private var spansOneDay: Bool {
        guard let first = semanticSnapshots.first?.date, let last = semanticSnapshots.last?.date else { return false }
        return last.timeIntervalSince(first) <= 30 * 3600
    }

    /// The curve covers more than about a year (the year is shown).
    private var spansYears: Bool {
        guard let first = semanticSnapshots.first?.date, let last = semanticSnapshots.last?.date else { return false }
        return last.timeIntervalSince(first) > 330 * 86400
    }

    /// Under the x axis: M.d; HH:mm for a one-day intraday curve; yyyy.M over more than a year.
    private func axisLabel(_ date: Date) -> String {
        if isSubDaily && spansOneDay { return format(date, "HH:mm") }
        return format(date, spansYears ? "yyyy.M" : "M.d")
    }

    /// While scrubbing and at the bottom right: M.d (yyyy.M.d over more than a year), with the time for an intraday
    /// curve.
    private func scrubLabel(_ date: Date) -> String {
        guard isSubDaily else { return format(date, spansYears ? "yyyy.M.d" : "M.d") }
        return format(date, spansOneDay ? "HH:mm" : "M.d HH:mm")
    }

    /// One formatter per pattern (making one is slow, and labels are drawn every frame while the curve moves).
    private static var formatters: [String: DateFormatter] = [:]

    private func format(_ date: Date, _ pattern: String) -> String {
        if let formatter = Self.formatters[pattern] { return formatter.string(from: date) }
        let formatter = DateFormatter()
        formatter.dateFormat = pattern
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        Self.formatters[pattern] = formatter
        return formatter.string(from: date)
    }
    
    private func clampScroll(_ value: Double, length: Double) -> Double {
        let upper = max(0, maxX - length)
        return min(max(value, 0), upper)
    }

    private func fitFullDomain() {
        domainLength = maxX
        scrollPosition = 0
    }

    private func playLaunchAnimation() {
        isLaunchAnimating = true
        Self.hasPlayedLineAnimation = true
        lineProgress = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.timingCurve(0.85, 0.0, 0.2, 1.0, duration: 1.3)) {
                lineProgress = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) {
            isLaunchAnimating = false
            onLaunchAnimationFinished?()

            if let snapshotsToApply = pendingSnapshots {
                pendingSnapshots = nil
                applyDisplayedSnapshots(snapshotsToApply)
            } else {
                // Deposits / withdrawals that changed while the line was drawing itself in.
                refreshMarkers()
            }
        }
    }

    private func applySnapshotsAfterLaunchIfNeeded(_ newSnapshots: [AssetChartSnapshot]) {
        guard !newSnapshots.isEmpty else { return }

        if isLaunchAnimating {
            pendingSnapshots = newSnapshots
        } else if displayedSnapshots.isEmpty, !Self.hasPlayedLineAnimation {
            let sortedSnapshots = ordered(newSnapshots)
            sourceSnapshots = sortedSnapshots
            let initialSnapshots = rangeSnapshots(
                from: sortedSnapshots,
                range: selectedRange
            )
            displayedSnapshots = initialSnapshots
            semanticSnapshots = initialSnapshots
            snapPlotHeights()
            shownMarkers = currentMarkers
            fitFullDomain()
            playLaunchAnimation()
        } else {
            applyDisplayedSnapshots(newSnapshots)
        }
    }

    private func applyDisplayedSnapshots(_ newSnapshots: [AssetChartSnapshot]) {
        let sortedSnapshots = ordered(newSnapshots)
        sourceSnapshots = sortedSnapshots

        animateDisplayedSnapshots(
            to: rangeSnapshots(
                from: sortedSnapshots,
                range: selectedRange
            )
        )
    }

    private func animateDisplayedSnapshots(to targetSnapshots: [AssetChartSnapshot]) {
        guard !targetSnapshots.isEmpty else { return }
        // Match both curves to the same horizontal sample positions before changing heights.
        let count = max(displayedSnapshots.count, targetSnapshots.count)
        let target = resampleSnapshots(targetSnapshots, count: count)
        semanticSnapshots = targetSnapshots
        displayedSnapshots = target
        fitFullDomain()
        animatePlotHeights()
        refreshMarkers()
    }

    private static func plotHeights(
        for snapshots: [AssetChartSnapshot],
        metric: PortfolioTrendMetric,
        principal: Double,
        direct: Bool
    ) -> [Double] {
        let values = snapshots.map { direct ? $0.value : metric.value(for: $0.value, principal: principal) }
        let domain = metric.plotDomain(for: values)
        let span = domain.upperBound - domain.lowerBound
        return values.map { ($0 - domain.lowerBound) / span }
    }

    /// The heights of the points shown now, at once (no morph).
    private func snapPlotHeights() {
        heights = TrendMorph(Self.plotHeights(for: displayedSnapshots, metric: metric, principal: principal,
                                              direct: plotsReturnsDirectly))
    }

    /// Eases the curve to the heights of the points shown now. Drawn frame by frame on the display's clock; a new
    /// curve arriving mid-morph carries on from where the line is, at the speed it is moving, rather than stopping
    /// and starting over.
    private func animatePlotHeights() {
        let target = Self.plotHeights(for: displayedSnapshots, metric: metric, principal: principal,
                                      direct: plotsReturnsDirectly)
        let now = Date.now
        var current = heights.values(at: now)
        var velocity = heights.velocities(at: now)
        if current.count != target.count {
            current = VerticalTrendMorph.resample(current, count: target.count)
            velocity = VerticalTrendMorph.resample(velocity, count: target.count)
        }
        guard !reduceMotion, !current.isEmpty, current != target else {
            heights = TrendMorph(target)
            return
        }
        heights = TrendMorph(from: current, velocity: velocity, to: target, start: now, duration: 0.85)
        runFrames()
    }

    /// Green ↔ red through the colours in between.
    private func animateColour(up: Bool) {
        let target: [Double] = [up ? 1 : 0]
        let now = Date.now
        let current = greenness.values(at: now)
        guard !reduceMotion, current.count == 1, current != target else {
            greenness = TrendMorph(target)
            return
        }
        greenness = TrendMorph(from: current, velocity: greenness.velocities(at: now), to: target, start: now,
                               duration: 0.85)
        runFrames()
    }

    /// The markers for the curve shown now: new ones pop in as the curve settles, gone ones shrink away.
    private func refreshMarkers() {
        let next = currentMarkers
        guard next != shownMarkers else { return }
        let previous = shownMarkers
        shownMarkers = next
        guard !reduceMotion, Self.hasPlayedLineAnimation, !isLaunchAnimating else {
            markerFades = MarkerFades()
            return
        }
        let now = Date.now
        let nextIDs = Set(next.map(\.id))
        let previousIDs = Set(previous.map(\.id))
        var fades = markerFades
        for marker in next where !previousIDs.contains(marker.id) {
            fades.leaving[marker.id] = nil
            fades.appearing[marker.id] = now.addingTimeInterval(MarkerFades.appearDelay)
        }
        for marker in previous where !nextIDs.contains(marker.id) {
            fades.appearing[marker.id] = nil
            fades.leaving[marker.id] = (marker, now)
        }
        markerFades = fades
        if !fades.isEmpty { runFrames() }
    }

    /// Redraws every frame until the curve, its colour and its markers have all settled.
    private func runFrames() {
        let end = max(heights.end, greenness.end, markerFades.end)
        let remaining = end.timeIntervalSinceNow
        guard remaining > 0 else { return }
        isAnimatingFrames = true
        frameDriver?.cancel()
        frameDriver = Task { @MainActor in
            try? await Task.sleep(for: .seconds(remaining + 0.05))
            guard !Task.isCancelled else { return }
            finishFrames()
        }
    }

    private func finishFrames() {
        isAnimatingFrames = false
        markerFades = MarkerFades()
    }

    private func resampleSnapshots(
        _ snapshots: [AssetChartSnapshot],
        count: Int
    ) -> [AssetChartSnapshot] {
        guard !snapshots.isEmpty else { return [] }
        guard count > 1 else { return Array(snapshots.prefix(1)) }
        guard snapshots.count > 1 else {
            return Array(repeating: snapshots[0], count: count)
        }

        return (0..<count).map { index in
            interpolatedSnapshot(
                in: snapshots,
                targetIndex: index,
                targetCount: count
            )
        }
    }

    private func interpolatedSnapshot(
        in snapshots: [AssetChartSnapshot],
        targetIndex: Int,
        targetCount: Int
    ) -> AssetChartSnapshot {
        guard let firstSnapshot = snapshots.first else {
            return AssetChartSnapshot(date: Date(), value: 0, isRecorded: false)
        }
        guard snapshots.count > 1, targetCount > 1 else { return firstSnapshot }

        let oldMaxIndex = Double(snapshots.count - 1)
        let targetMaxIndex = Double(targetCount - 1)
        let mappedIndex = Double(targetIndex) / targetMaxIndex * oldMaxIndex
        let lowerIndex = Int(floor(mappedIndex))
        let upperIndex = min(snapshots.count - 1, Int(ceil(mappedIndex)))

        guard lowerIndex != upperIndex else {
            return snapshots[lowerIndex]
        }

        let progress = mappedIndex - Double(lowerIndex)
        let lowerSnapshot = snapshots[lowerIndex]
        let upperSnapshot = snapshots[upperIndex]
        let value = lowerSnapshot.value + (upperSnapshot.value - lowerSnapshot.value) * progress
        let time = lowerSnapshot.date.timeIntervalSince1970 +
            (upperSnapshot.date.timeIntervalSince1970 - lowerSnapshot.date.timeIntervalSince1970) * progress

        return AssetChartSnapshot(
            date: Date(timeIntervalSince1970: time),
            value: value,
            isRecorded: false
        )
    }

    private func snapshotsSignature(_ snapshots: [AssetChartSnapshot]) -> String {
        snapshots.map { "\($0.date.timeIntervalSince1970)-\($0.value)-\($0.isRecorded)" }.joined(separator: "|")
    }

    private var visibleSnapshots: [AssetChartSnapshot] {
        let start = max(0, Int(floor(scrollPosition)))
        let end = min(
            normalizedSnapshots.count - 1,
            Int(ceil(scrollPosition + domainLength))
        )

        guard start <= end else { return normalizedSnapshots }
        return Array(normalizedSnapshots[start...end])
    }

    private var visibleYDomain: ClosedRange<Double> {
        metric.plotDomain(for: normalizedSnapshots.map { plotValue($0.value) })
    }

    private var xAxisValues: [Int] {
        let count = displayedSnapshots.count
        guard count > 1 else { return count == 1 ? [0] : [] }

        let visibleStart = max(0, Int(floor(scrollPosition)))
        let visibleEnd = min(count - 1, Int(ceil(scrollPosition + domainLength)))

        guard visibleStart < visibleEnd else {
            return [visibleStart]
        }

        let first = visibleStart
        let second = visibleStart + Int(round(Double(visibleEnd - visibleStart) / 3.0))
        let third = visibleStart + Int(round(Double(visibleEnd - visibleStart) * 2.0 / 3.0))
        let last = visibleEnd

        var seenDates = Set<String>()
        return Array(Set([first, second, third, last]))
            .sorted()
            .filter { index in
                let key = semanticDateKey(for: index)
                guard !seenDates.contains(key) else { return false }
                seenDates.insert(key)
                return true
            }
    }

    private func semanticIndex(forDisplayIndex displayIndex: Int) -> Int {
        guard !semanticSnapshots.isEmpty else { return 0 }
        guard normalizedSnapshots.count > 1, semanticSnapshots.count > 1 else { return 0 }

        let clampedDisplayIndex = min(
            max(displayIndex, 0),
            normalizedSnapshots.count - 1
        )
        let ratio = Double(clampedDisplayIndex) / Double(normalizedSnapshots.count - 1)
        let semanticIndex = Int(round(ratio * Double(semanticSnapshots.count - 1)))

        return min(max(semanticIndex, 0), semanticSnapshots.count - 1)
    }

    private func displayIndex(forSemanticIndex semanticIndex: Int) -> Int {
        Self.displayIndex(forSemanticIndex: semanticIndex, semanticCount: semanticSnapshots.count,
                          displayCount: normalizedSnapshots.count)
    }

    private static func displayIndex(forSemanticIndex semanticIndex: Int, semanticCount: Int, displayCount: Int) -> Int {
        guard displayCount > 1, semanticCount > 1 else { return 0 }

        let clampedSemanticIndex = min(max(semanticIndex, 0), semanticCount - 1)
        let ratio = Double(clampedSemanticIndex) / Double(semanticCount - 1)
        let displayIndex = Int(round(ratio * Double(displayCount - 1)))

        return min(max(displayIndex, 0), displayCount - 1)
    }

    private func semanticSnapshot(for displayIndex: Int) -> AssetChartSnapshot {
        if semanticSnapshots.isEmpty {
            let fallbackIndex = min(
                max(displayIndex, 0),
                max(normalizedSnapshots.count - 1, 0)
            )
            return normalizedSnapshots[fallbackIndex]
        }

        return semanticSnapshots[semanticIndex(forDisplayIndex: displayIndex)]
    }

    private func semanticDateKey(for displayIndex: Int) -> String {
        format(semanticSnapshot(for: displayIndex).date, isSubDaily && spansOneDay ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd")
    }
    
    
    private func updateSelectedPoint(
        location: CGPoint,
        plotFrame: CGRect,
        proxy: ChartProxy,
        haptic: Bool
    ) {
        guard location.x >= plotFrame.minX,
              location.x <= plotFrame.maxX else { return }

        let localX = location.x - plotFrame.minX
        let ratio = max(0, min(1, localX / plotFrame.width))

        let visibleStart = scrollPosition
        let visibleEnd = scrollPosition + domainLength
        let xValue = visibleStart + Double(ratio) * (visibleEnd - visibleStart)

        guard !normalizedSnapshots.isEmpty else {
            selectedIndex = nil
            selectedAssetValue = nil
            return
        }

        let rawIndex = Int(round(xValue))

        let index: Int
        index = min(
            normalizedSnapshots.count - 1,
            max(0, rawIndex)
        )

        guard normalizedSnapshots.indices.contains(index) else {
            selectedIndex = nil
            selectedAssetValue = nil
            return
        }

        selectedIndex = index
        selectedAssetValue = semanticSnapshot(for: index).value

        if haptic, lastHapticIndex != index {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            lastHapticIndex = index
        }
    }
    
    private func formatMonthDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M.d"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        return formatter.string(from: date)
    }
    
    private var maxVisibleLineIndex: Int {
        guard normalizedSnapshots.count > 1 else { return 0 }
        let maxIndex = normalizedSnapshots.count - 1
        return min(maxIndex, max(0, Int(Double(maxIndex) * lineProgress)))
    }
    private func maxAnnotationAlignment(index: Int, count: Int) -> Alignment {
        if count < 3 { return .center }

        if index < 2 {
            return .leading
        } else if index > count - 3 {
            return .trailing
        } else {
            return .center
        }
    }

    private func maxAnnotationXOffset(index: Int, count: Int) -> CGFloat {
        if count < 3 { return 0 }

        if index < 2 {
            return 5
        } else if index > count - 3 {
            return -5
        } else {
            return 0
        }
    }
}

/// Values easing from `from` to `to` over `duration` on the app's ease-in-out curve (cubic-bezier 0.85, 0, 0.2, 1 —
/// the allocation chart's): a slow start, a fast middle and a soft landing, never linear. A morph can start moving
/// (`velocity`, per second), so one that replaces another mid-way keeps the speed the values had.
struct TrendMorph {
    var from: [Double]
    var velocity: [Double]
    var to: [Double]
    var start: Date
    var duration: Double

    /// Resting at `values`.
    init(_ values: [Double]) {
        self.init(from: values, velocity: Array(repeating: 0, count: values.count), to: values, start: .distantPast,
                  duration: 0)
    }

    init(from: [Double], velocity: [Double], to: [Double], start: Date, duration: Double) {
        self.from = from
        self.velocity = velocity.count == from.count ? velocity : Array(repeating: 0, count: from.count)
        self.to = to
        self.start = start
        self.duration = duration
    }

    var end: Date { start.addingTimeInterval(duration) }

    private func progress(at date: Date) -> Double? {
        guard duration > 0, from.count == to.count else { return nil }
        let progress = date.timeIntervalSince(start) / duration
        return progress < 1 ? max(progress, 0) : nil
    }

    func values(at date: Date) -> [Double] {
        guard let s = progress(at: date) else { return to }
        let arrive = Self.ease(s)
        let s3 = s * s * s, s4 = s3 * s, s5 = s4 * s
        // The speed it already had fades out over the morph (zero at both ends).
        let carry = (s - 6 * s3 + 8 * s4 - 3 * s5) * duration
        return from.indices.map { from[$0] + (to[$0] - from[$0]) * arrive + velocity[$0] * carry }
    }

    func velocities(at date: Date) -> [Double] {
        guard let s = progress(at: date) else { return Array(repeating: 0, count: to.count) }
        let arrive = Self.easeSlope(s) / duration
        let s2 = s * s, s3 = s2 * s, s4 = s3 * s
        let carry = 1 - 18 * s2 + 32 * s3 - 15 * s4
        return from.indices.map { (to[$0] - from[$0]) * arrive + velocity[$0] * carry }
    }

    // MARK: Curve: cubic-bezier(0.85, 0, 0.2, 1)

    private static let x1 = 0.85, y1 = 0.0, x2 = 0.2, y2 = 1.0

    private static func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }

    private static func bezierSlope(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b)
    }

    /// The curve's parameter at time `x` (Newton, then bisection where the slope is flat).
    private static func parameter(_ x: Double) -> Double {
        var t = x
        for _ in 0..<8 {
            let error = bezier(t, x1, x2) - x
            let slope = bezierSlope(t, x1, x2)
            if abs(error) < 1e-6 { return t }
            if abs(slope) < 1e-6 { break }
            t = min(max(t - error / slope, 0), 1)
        }
        var low = 0.0, high = 1.0
        t = x
        for _ in 0..<30 {
            let value = bezier(t, x1, x2)
            if abs(value - x) < 1e-6 { break }
            if value < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return t
    }

    /// Progress along the curve at time fraction `s`.
    static func ease(_ s: Double) -> Double { bezier(parameter(s), y1, y2) }

    /// d(progress) / d(time fraction) at `s`.
    static func easeSlope(_ s: Double) -> Double {
        let t = parameter(s)
        let dx = bezierSlope(t, x1, x2)
        return dx > 1e-6 ? bezierSlope(t, y1, y2) / dx : 0
    }
}

/// The marker of a deposit (入金 / 转入: up, blue) or a withdrawal (出金 / 转出: down, orange) on the value curve.
struct FlowMarkerSymbol: View {
    let isIn: Bool

    static func color(isIn: Bool) -> Color { isIn ? .blue : .orange }

    var body: some View {
        Image(systemName: isIn ? "arrow.up" : "arrow.down")
            .font(.system(size: 7, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 13, height: 13)
            .background(Self.color(isIn: isIn), in: Circle())
            .overlay(Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 1.5).padding(-1.5))
            .accessibilityLabel(isIn ? "入金" : "出金")
    }
}

#Preview {
    AssetTrendChart(
        snapshots: testAssetSnapshots,
        principal: 100_000,
        currentTotalAsset: testAssetSnapshots.last?.value ?? 100_000,
        selectedAssetValue: .constant(nil)
    )
    .frame(height: 260)
    .padding()
}
