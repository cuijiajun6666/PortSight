//
//  资产走势图.swift
//  PortSight
//
//  Created by Chris Cui on 29/4/2026.
//

import SwiftUI
import AppKit
import Charts
import SwiftData
import PortSightKit

struct AssetTrendChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let snapshots: [AssetChartSnapshot]
    let principal: Double
    let currentTotalAsset: Double
    let metric: PortfolioTrendMetric
    let showsRangePicker: Bool
    let chartHeight: CGFloat
    /// false: only the curve — no date labels, amount labels or grid lines (the compact 总览 header).
    var showsAxes: Bool = true
    /// false: every snapshot is drawn (intraday points, IBKR report days); true: one per New York day.
    var groupsByDay: Bool = true
    /// How dates are written on the axis, in the hover readout and in the corner.
    var dateStyle: AssetTrendDateStyle = .builtIn
    /// Deposits and withdrawals marked on the curve (入金 up, 出金 down); their amount shows in the hover readout.
    var markers: [AssetTrendMarker] = []
    let onLaunchAnimationFinished: (() -> Void)?

    @State private var domainLength: Double = 1
    @State private var scrollPosition: Double = 0

    @State private var gestureStartDomainLength: Double = 1
    @State private var gestureStartScrollPosition: Double = 0
    @State private var gestureAnchorX: Double?
    
    @State private var isInspecting = false
    @State private var isTouching = false
    @State private var selectedIndex: Int? = nil
    @State private var selectedXPosition: CGFloat? = nil
    @Binding var selectedAssetValue: Double?
    
    @State private var longPressStartLocation: CGPoint? = nil
    
    @State private var lastHapticIndex: Int? = nil
    @State private var longPressTask: DispatchWorkItem?

    private var maxX: Double {
        Double(max(normalizedSnapshots.count - 1, 1))
    }
    
    @State private var touchStartLocation: CGPoint?
    
    @State private var renderedYValues: [Double]
    @State private var morphTask: Task<Void, Never>?
    @State private var lineProgress: Double = 0
    @State private var sourceSnapshots: [AssetChartSnapshot]
    @State private var displayedSnapshots: [AssetChartSnapshot]
    @State private var semanticSnapshots: [AssetChartSnapshot]
    @State private var pendingSnapshots: [AssetChartSnapshot]?
    @State private var isLaunchAnimating = false
    @State private var localRange: AssetTrendRange = .all
    private let rangeSelection: Binding<AssetTrendRange>?

    private var selectedRange: AssetTrendRange {
        rangeSelection?.wrappedValue ?? localRange
    }

    private var selectedRangeBinding: Binding<AssetTrendRange> {
        Binding(get: { selectedRange }, set: { range in
            if let rangeSelection {
                rangeSelection.wrappedValue = range
            } else {
                localRange = range
            }
        })
    }
    private static var hasPlayedLineAnimation = false

    init(
        snapshots: [AssetChartSnapshot],
        principal: Double,
        currentTotalAsset: Double,
        selectedAssetValue: Binding<Double?>,
        metric: PortfolioTrendMetric = .amount,
        showsRangePicker: Bool = false,
        chartHeight: CGFloat = 220,
        rangeSelection: Binding<AssetTrendRange>? = nil,
        showsAxes: Bool = true,
        groupsByDay: Bool = true,
        dateStyle: AssetTrendDateStyle = .builtIn,
        markers: [AssetTrendMarker] = [],
        onLaunchAnimationFinished: (() -> Void)? = nil
    ) {
        self.showsAxes = showsAxes
        self.groupsByDay = groupsByDay
        self.dateStyle = dateStyle
        self.markers = markers
        self.snapshots = snapshots
        self.principal = principal
        self.currentTotalAsset = currentTotalAsset
        self.metric = metric
        self.showsRangePicker = showsRangePicker
        self.chartHeight = chartHeight
        self.rangeSelection = rangeSelection
        self.onLaunchAnimationFinished = onLaunchAnimationFinished
        _selectedAssetValue = selectedAssetValue
        let sortedSnapshots = Self.prepared(snapshots, byDay: groupsByDay)
        let initialSnapshots = Self.rangeSnapshots(from: sortedSnapshots, range: rangeSelection?.wrappedValue ?? .all)
        _sourceSnapshots = State(initialValue: sortedSnapshots)
        _displayedSnapshots = State(initialValue: initialSnapshots)
        _semanticSnapshots = State(initialValue: initialSnapshots)
        _renderedYValues = State(initialValue: Self.plotHeights(for: initialSnapshots, metric: metric, principal: principal))
    }

    /// Oldest first; one per New York day when `byDay` (the built-in curve), else every snapshot.
    private static func prepared(_ snapshots: [AssetChartSnapshot], byDay: Bool) -> [AssetChartSnapshot] {
        byDay ? uniqueDailySnapshots(snapshots) : snapshots.sorted { $0.date < $1.date }
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
    
    private static func rangeSnapshots(
        from snapshots: [AssetChartSnapshot],
        range: AssetTrendRange
    ) -> [AssetChartSnapshot] {
        // Callers pass prepared snapshots (oldest first, grouped by day where that applies).
        let sortedSnapshots = snapshots
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
            Chart {
                chartContent
            }
        .chartPlotStyle { plotArea in
            plotArea
                .mask(alignment: .leading) {
                    Rectangle()
                        .scaleEffect(x: lineProgress, anchor: .leading)
                }
        }
        .onAppear {
            if sourceSnapshots.isEmpty, !snapshots.isEmpty {
                sourceSnapshots = Self.prepared(snapshots, byDay: groupsByDay)
            }

            if displayedSnapshots.isEmpty, !sourceSnapshots.isEmpty {
                let initialSnapshots = Self.rangeSnapshots(
                    from: sourceSnapshots,
                    range: selectedRange
                )
                displayedSnapshots = initialSnapshots
                semanticSnapshots = initialSnapshots
            }

            guard !Self.hasPlayedLineAnimation else {
                lineProgress = 1
                applySnapshotsAfterLaunchIfNeeded(snapshots)
                onLaunchAnimationFinished?()
                return
            }

            guard !normalizedSnapshots.isEmpty else {
                onLaunchAnimationFinished?()
                return
            }

            playLaunchAnimation()
        }
        .onChange(of: snapshots.map { "\($0.date.timeIntervalSince1970)-\($0.value)" }.joined(separator: "|")) { _, _ in
            resetInspection()
            applySnapshotsAfterLaunchIfNeeded(snapshots)
        }
        .onChange(of: selectedRange) { _, range in
            resetInspection()
            animateDisplayedSnapshots(to: Self.rangeSnapshots(from: sourceSnapshots, range: range))
        }
        .onChange(of: metric) { _, _ in
            resetInspection()
            animatePlotHeights()
        }
        .onChange(of: principal) { _, _ in
            if metric == .returnRate { animatePlotHeights() }
        }
        .onDisappear {
            morphTask?.cancel()
            morphTask = nil
            resetInspection()
        }
        .onChange(of: normalizedSnapshots.count) { _, count in
            fitFullDomain()

            guard count > 0, Self.hasPlayedLineAnimation else { return }
            lineProgress = 1
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
                        Text(formatMonthDay(semanticSnapshot(for: index).date))
                    }
                }
            }
        }
        .chartXAxis(showsAxes ? .automatic : .hidden)
        .chartYAxis(showsAxes ? .automatic : .hidden)
        .chartYAxis {
            AxisMarks(values: [0.0, 0.25, 0.5, 0.75, 1.0]) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let height = value.as(Double.self) {
                        let number = visibleYDomain.lowerBound + height * (visibleYDomain.upperBound - visibleYDomain.lowerBound)
                        Group {
                            if metric == .returnRate {
                                Text(number / 100, format: .percent.precision(.fractionLength(0...2)))
                            } else {
                                Text(number, format: .number.precision(.fractionLength(0)))
                            }
                        }
                        // Keep label width identical across units so points never drift sideways.
                        .frame(width: 58, alignment: .trailing)
                    }
                }
            }
        }
        .opacity(metric == .returnRate && principal <= 0 ? 0 : 1)
        .overlay {
            if metric == .returnRate && principal <= 0 {
                Text("暂无收益率数据").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(height: chartHeight)
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plotFrame = proxy.plotFrame.map { geo[$0] } ?? .zero
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            isInspecting = true
                            updateSelectedPoint(location: location, plotFrame: plotFrame, proxy: proxy, haptic: false)
                        case .ended:
                            resetInspection()
                        }
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isTouching = true

                                if touchStartLocation == nil {
                                    touchStartLocation = value.location
                                    gestureStartScrollPosition = scrollPosition

                                    let task = DispatchWorkItem {
                                        isInspecting = true

                                        updateSelectedPoint(
                                            location: value.location,
                                            plotFrame: plotFrame,
                                            proxy: proxy,
                                            haptic: true
                                        )
                                    }

                                    longPressTask = task
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: task)
                                }

                                if isInspecting {
                                    updateSelectedPoint(
                                        location: value.location,
                                        plotFrame: plotFrame,
                                        proxy: proxy,
                                        haptic: true
                                    )
                                } else {
                                    guard let start = touchStartLocation else { return }

                                    let dx = value.location.x - start.x
                                    let dy = value.location.y - start.y

                                    // ✅ 先处理纵向滑动，不管 canScroll 是 true 还是 false
                                    if abs(dy) > abs(dx), abs(dy) > 4 {
                                        print("纵向滑动")
                                        longPressTask?.cancel()
                                        longPressTask = nil

                                        isTouching = false
                                        isInspecting = false
                                        selectedIndex = nil
                                        selectedXPosition = nil
                                        selectedAssetValue = nil
                                        touchStartLocation = nil
                                        lastHapticIndex = nil

                                        return
                                    }

                                    
                                }
                            }
                            .onEnded { _ in
                                longPressTask?.cancel()
                                longPressTask = nil

                                isTouching = false
                                isInspecting = false
                                selectedIndex = nil
                                selectedXPosition = nil
                                selectedAssetValue = nil
                                touchStartLocation = nil
                                lastHapticIndex = nil
                                gestureStartScrollPosition = scrollPosition
                            }
                    )
            }
        }
        .onChange(of: domainLength) { _, newValue in
            if newValue >= maxX {
                scrollPosition = 0
            } else {
                scrollPosition = clampScroll(scrollPosition, length: newValue)
            }

            gestureStartScrollPosition = scrollPosition
        }
        .onAppear {
            fitFullDomain()
        }
        .overlay(alignment: .bottomTrailing) {
            if showsAxes {
            Text(latestVisibleDateText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.trailing, 4)
                .offset(y: 2)
            }
        }
            
            if showsRangePicker {
                DesktopCapsulePicker(title: "资产趋势范围", options: AssetTrendRange.allCases,
                                     selection: selectedRangeBinding, label: { $0.rawValue })
            }
        }
    }

    @ChartContentBuilder
    private var chartContent: some ChartContent {
        baseTrendMarks
        selectedHighlightMarks
        maxAnnotationMark
        flowMarks
        selectedPointMarks
    }

    /// 入金 (up) and 出金 (down) on the point that first includes them.
    @ChartContentBuilder
    private var flowMarks: some ChartContent {
        ForEach(markerSpots) { spot in
            PointMark(
                x: .value("Flow", spot.displayIndex),
                y: .value("Height", renderedHeight(at: spot.displayIndex))
            )
            .symbol {
                Image(systemName: spot.isIn ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, spot.isIn ? DesktopTheme.blue : DesktopTheme.orange)
                    .accessibilityLabel(spot.text)
            }
        }
    }

    /// The markers grouped by the point they sit on (several flows on one day show as one mark).
    private var markerSpots: [AssetTrendMarkerSpot] {
        guard !markers.isEmpty, let first = semanticSnapshots.first?.date, let last = semanticSnapshots.last?.date
        else { return [] }
        var bySemanticIndex: [Int: [AssetTrendMarker]] = [:]
        for marker in markers where marker.date >= first.addingTimeInterval(-1) && marker.date <= last.addingTimeInterval(1) {
            guard let index = semanticSnapshots.indices.min(by: {
                abs(semanticSnapshots[$0].date.timeIntervalSince(marker.date))
                    < abs(semanticSnapshots[$1].date.timeIntervalSince(marker.date))
            }) else { continue }
            bySemanticIndex[index, default: []].append(marker)
        }
        return bySemanticIndex.keys.sorted().map { index in
            AssetTrendMarkerSpot(semanticIndex: index, displayIndex: displayIndex(forSemanticIndex: index),
                                 markers: bySemanticIndex[index] ?? [])
        }
    }

    /// 「入金 +$1,000.00」 for the flows on the hovered point, if any.
    private func flowText(forDisplayIndex index: Int) -> String? {
        let semantic = semanticIndex(forDisplayIndex: index)
        return markerSpots.first { $0.semanticIndex == semantic }?.text
    }

    @ChartContentBuilder
    private var baseTrendMarks: some ChartContent {
        ForEach(normalizedSnapshots.indices, id: \.self) { i in
            LineMark(
                x: .value("Day", i),
                y: .value("Height", renderedHeight(at: i)),
                series: .value("Series", "base")
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(lineColor.opacity(selectedIndex == nil ? 1.0 : 0.3))

            AreaMark(
                x: .value("Day", i),
                yStart: .value("Min", minSnapshotValue),
                yEnd: .value("Height", renderedHeight(at: i))
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    gradient: Gradient(colors: [
                        lineColor.opacity(selectedIndex == nil ? 0.3 : 0.1),
                        .clear
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    @ChartContentBuilder
    private var selectedHighlightMarks: some ChartContent {
        if let selectedIndex, selectedIndex > 0 {
            ForEach(0...selectedIndex, id: \.self) { i in
                LineMark(
                    x: .value("Day", i),
                    y: .value("Height", renderedHeight(at: i)),
                    series: .value("Series", "highlight")
                )
                .interpolationMethod(selectedIndex < 2 ? .linear : .catmullRom)
                .foregroundStyle(lineColor)
            }
        }
    }

    @ChartContentBuilder
    private var maxAnnotationMark: some ChartContent {
        if let max = visibleMax {
            PointMark(
                x: .value("Max", max.index),
                y: .value("Height", renderedHeight(at: max.index))
            )
            .symbolSize(0)
            .foregroundStyle(lineColor.opacity(isTouching ? 0 : 1))
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
    private var selectedPointMarks: some ChartContent {
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
            .annotation(position: .top, alignment: .center, spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                // A small capsule keeps the top grid line from cutting through the date (and any flow's amount).
                Text([formatMonthDay(semanticSnapshot(for: selectedIndex).date), flowText(forDisplayIndex: selectedIndex)]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
            }

            PointMark(
                x: .value("Selected", selectedIndex),
                y: .value("Height", renderedHeight(at: selectedIndex))
            )
            .symbolSize(60)
            .foregroundStyle(lineColor)
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
        metric.value(for: assetValue, principal: principal)
    }

    private func resetInspection() {
        longPressTask?.cancel()
        longPressTask = nil
        isTouching = false
        isInspecting = false
        selectedIndex = nil
        selectedXPosition = nil
        selectedAssetValue = nil
        touchStartLocation = nil
        lastHapticIndex = nil
    }

    private var minSnapshotValue: Double {
        normalizedSnapshots.indices.map { renderedHeight(at: $0) }.min() ?? 0
    }
    
    private var lineColor: Color {
        currentTotalAsset - principal >= 0 ? .green : .red
    }
    
    private var latestVisibleDateText: String {
        guard !semanticSnapshots.isEmpty else { return "" }

        let visibleEnd = min(
            normalizedSnapshots.count - 1,
            Int(ceil(scrollPosition + domainLength))
        )

        let semanticIndex = semanticIndex(forDisplayIndex: visibleEnd)
        guard semanticSnapshots.indices.contains(semanticIndex) else { return "" }

        return dateStyle.text(semanticSnapshots[semanticIndex].date)
    }
    
    private func clampScroll(_ value: Double, length: Double) -> Double {
        let upper = max(0, maxX - length)
        return min(max(value, 0), upper)
    }

    private func fitFullDomain() {
        domainLength = maxX
        scrollPosition = 0
        gestureStartScrollPosition = 0
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
            }
        }
    }

    private func applySnapshotsAfterLaunchIfNeeded(_ newSnapshots: [AssetChartSnapshot]) {
        guard !newSnapshots.isEmpty else { return }

        if isLaunchAnimating {
            pendingSnapshots = newSnapshots
        } else if displayedSnapshots.isEmpty, !Self.hasPlayedLineAnimation {
            let sortedSnapshots = Self.prepared(newSnapshots, byDay: groupsByDay)
            sourceSnapshots = sortedSnapshots
            let initialSnapshots = Self.rangeSnapshots(
                from: sortedSnapshots,
                range: selectedRange
            )
            displayedSnapshots = initialSnapshots
            semanticSnapshots = initialSnapshots
            fitFullDomain()
            playLaunchAnimation()
        } else {
            applyDisplayedSnapshots(newSnapshots)
        }
    }

    private func applyDisplayedSnapshots(_ newSnapshots: [AssetChartSnapshot]) {
        let sortedSnapshots = Self.prepared(newSnapshots, byDay: groupsByDay)
        sourceSnapshots = sortedSnapshots

        animateDisplayedSnapshots(
            to: Self.rangeSnapshots(
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
    }

    private static func plotHeights(
        for snapshots: [AssetChartSnapshot],
        metric: PortfolioTrendMetric,
        principal: Double
    ) -> [Double] {
        let values = snapshots.map { metric.value(for: $0.value, principal: principal) }
        let domain = metric.plotDomain(for: values)
        let span = domain.upperBound - domain.lowerBound
        return values.map { ($0 - domain.lowerBound) / span }
    }

    private func renderedHeight(at index: Int) -> Double {
        if renderedYValues.indices.contains(index) { return renderedYValues[index] }
        guard normalizedSnapshots.indices.contains(index) else { return 0 }
        let domain = visibleYDomain
        return (plotValue(normalizedSnapshots[index].value) - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
    }

    private func animatePlotHeights() {
        morphTask?.cancel()
        let target = Self.plotHeights(for: displayedSnapshots, metric: metric, principal: principal)
        let start = VerticalTrendMorph.resample(renderedYValues, count: target.count)
        guard !reduceMotion, !start.isEmpty, start != target else {
            renderedYValues = target
            return
        }
        renderedYValues = start
        morphTask = Task { @MainActor in
            let began = ProcessInfo.processInfo.systemUptime
            let duration = 0.72
            while !Task.isCancelled {
                let progress = min((ProcessInfo.processInfo.systemUptime - began) / duration, 1)
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    renderedYValues = VerticalTrendMorph.values(from: start, to: target, progress: progress)
                }
                if progress >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
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
        guard normalizedSnapshots.count > 1, semanticSnapshots.count > 1 else { return 0 }

        let clampedSemanticIndex = min(
            max(semanticIndex, 0),
            semanticSnapshots.count - 1
        )
        let ratio = Double(clampedSemanticIndex) / Double(semanticSnapshots.count - 1)
        let displayIndex = Int(round(ratio * Double(normalizedSnapshots.count - 1)))

        return min(max(displayIndex, 0), normalizedSnapshots.count - 1)
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

    /// Axis labels are deduplicated by what they say.
    private func semanticDateKey(for displayIndex: Int) -> String {
        dateStyle.text(semanticSnapshot(for: displayIndex).date)
    }
    
    private var canScroll: Bool {
        domainLength < maxX
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
        selectedXPosition = location.x
        selectedAssetValue = semanticSnapshot(for: index).value

        if haptic, lastHapticIndex != index {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            lastHapticIndex = index
        }
    }
    
    private func formatMonthDay(_ date: Date) -> String {
        dateStyle.text(date)
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

/// A deposit or withdrawal marked on the curve (入金 up, 出金 down); its amount shows in the hover readout.
struct AssetTrendMarker: Identifiable, Equatable {
    let id: String
    /// The point it sits on (the first that includes it).
    let date: Date
    /// 入金 / 出金 / 转入 / 转出.
    let title: String
    /// USD: in positive, out negative.
    let amount: Double
    var isIn: Bool { amount >= 0 }
}

/// The markers on one point.
private struct AssetTrendMarkerSpot: Identifiable {
    let semanticIndex: Int
    let displayIndex: Int
    let markers: [AssetTrendMarker]

    var id: Int { semanticIndex }
    var isIn: Bool { markers.reduce(0) { $0 + $1.amount } >= 0 }
    /// 「入金 +$1,000.00」, several joined by 「 · 」.
    var text: String { markers.map { $0.title + " " + DesktopTheme.signedMoney($0.amount) }.joined(separator: " · ") }
}

/// How the curve's dates are written.
enum AssetTrendDateStyle: Equatable {
    /// M.d in a time zone (IBKR report days: UTC).
    case day(TimeZone)
    /// HH:mm, local (a 1天 range).
    case time
    /// M.d HH:mm, local (a 1周 range).
    case dayTime

    /// The built-in curve: New York days, as it always was.
    static var builtIn: AssetTrendDateStyle { .day(TimeZone(identifier: "America/New_York") ?? .current) }

    func text(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch self {
        case .day(let zone):
            formatter.dateFormat = "M.d"
            formatter.timeZone = zone
        case .time:
            formatter.dateFormat = "HH:mm"
        case .dayTime:
            formatter.dateFormat = "M.d HH:mm"
        }
        return formatter.string(from: date)
    }
}
