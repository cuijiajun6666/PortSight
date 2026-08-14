//
//  资产走势图.swift
//  PortSight
//
//  Created by Chris Cui on 29/4/2026.
//

import SwiftUI
import Charts
import SwiftData

let testAssetSnapshots: [AssetChartSnapshot] = {
    var result: [AssetChartSnapshot] = []
    var value = 100_000.0

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!

    let startDate = calendar.date(from: DateComponents(
        year: 2026,
        month: 3,
        day: 1,
        hour: 12
    ))!

    for i in 0..<40 {
        value += Double.random(in: -1200...1600)

        let date = calendar.date(
            byAdding: .day,
            value: i,
            to: startDate
        )!

        result.append(
            AssetChartSnapshot(
                date: date,
                value: value
            )
        )
    }

    return result
}()


struct AssetChartSnapshot: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let isRecorded: Bool

    init(date: Date, value: Double, isRecorded: Bool = true) {
        self.date = date
        self.value = value
        self.isRecorded = isRecorded
    }
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

    let snapshots: [AssetChartSnapshot]
    let principal: Double
    let currentTotalAsset: Double
    let showsRangePicker: Bool
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
        showsRangePicker: Bool = false,
        onLaunchAnimationFinished: (() -> Void)? = nil
    ) {
        self.snapshots = snapshots
        self.principal = principal
        self.currentTotalAsset = currentTotalAsset
        self.showsRangePicker = showsRangePicker
        self.onLaunchAnimationFinished = onLaunchAnimationFinished
        _selectedAssetValue = selectedAssetValue
        let sortedSnapshots = Self.uniqueDailySnapshots(snapshots)
        _sourceSnapshots = State(initialValue: sortedSnapshots)
        _displayedSnapshots = State(initialValue: sortedSnapshots)
        _semanticSnapshots = State(initialValue: sortedSnapshots)
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
        let sortedSnapshots = Self.uniqueDailySnapshots(snapshots)
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
                sourceSnapshots = Self.uniqueDailySnapshots(snapshots)
            }

            if displayedSnapshots.isEmpty, !sourceSnapshots.isEmpty {
                let initialSnapshots = rangeSnapshots(
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
            applySnapshotsAfterLaunchIfNeeded(snapshots)
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
        .chartYScale(domain: visibleYDomain)
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
//        .chartYAxis {
//            AxisMarks { value in
//                AxisValueLabel()
//            }
//        }
        .frame(height: 220)
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plotFrame = geo[proxy.plotFrame!]
                Rectangle()
                    .fill(Color.white.opacity(-1))
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
            Text(latestVisibleDateText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.trailing, 4)
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

    @ChartContentBuilder
    private var chartContent: some ChartContent {
        baseTrendMarks
        selectedHighlightMarks
        maxAnnotationMark
        selectedPointMarks
    }

    @ChartContentBuilder
    private var baseTrendMarks: some ChartContent {
        ForEach(normalizedSnapshots.indices, id: \.self) { i in
            LineMark(
                x: .value("Day", i),
                y: .value("Asset", normalizedSnapshots[i].value),
                series: .value("Series", "base")
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(lineColor.opacity(selectedIndex == nil ? 1.0 : 0.3))

            AreaMark(
                x: .value("Day", i),
                yStart: .value("Min", minSnapshotValue),
                yEnd: .value("Asset", normalizedSnapshots[i].value)
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
                    y: .value("Asset", normalizedSnapshots[i].value),
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
                y: .value("Asset", max.value)
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
                Text("$\(max.value, specifier: "%.0f")")
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

            let minY = visibleYDomain.lowerBound
            let maxY = visibleYDomain.upperBound
            let range = maxY - minY

            RuleMark(
                x: .value("Selected Date", selectedIndex),
                yStart: .value("Start", minY + range * 0.1),
                yEnd: .value("End", maxY - range * 0.12)
            )
            .foregroundStyle(.gray.opacity(0.55))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .annotation(position: .top, alignment: .center) {
                Text(formatMonthDay(semanticSnapshot(for: selectedIndex).date))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 35)
            }

            PointMark(
                x: .value("Selected", selectedIndex),
                y: .value("Asset", normalizedSnapshots[selectedIndex].value)
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
                return (displayIndex(forSemanticIndex: start + offset), snapshot.value)
            }
            .max {
                if $0.value == $1.value {
                    return $0.index < $1.index
                }
                return $0.value < $1.value
            }
    }

    private var minSnapshotValue: Double {
        normalizedSnapshots.map(\.value).min() ?? 0
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

        let formatter = DateFormatter()
        formatter.dateFormat = "M.d"
        formatter.timeZone = TimeZone(identifier: "America/New_York")

        return formatter.string(from: semanticSnapshots[semanticIndex].date)
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
            let sortedSnapshots = Self.uniqueDailySnapshots(newSnapshots)
            sourceSnapshots = sortedSnapshots
            let initialSnapshots = rangeSnapshots(
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
        let sortedSnapshots = Self.uniqueDailySnapshots(newSnapshots)
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

        let targetPointCount = max(targetSnapshots.count, 1)
        let hasEnoughPointsForSmoothMorph = targetPointCount >= 7
        let renderPointCount = hasEnoughPointsForSmoothMorph
            ? max(displayedSnapshots.count, targetPointCount)
            : targetPointCount
        let startingSnapshots = resampleSnapshots(
            displayedSnapshots,
            count: renderPointCount
        )
        let targetDisplaySnapshots = resampleSnapshots(
            targetSnapshots,
            count: renderPointCount
        )

        guard snapshotsSignature(displayedSnapshots) != snapshotsSignature(targetDisplaySnapshots) else {
            semanticSnapshots = targetSnapshots
            return
        }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            displayedSnapshots = startingSnapshots
            semanticSnapshots = targetSnapshots
            fitFullDomain()
        }

        DispatchQueue.main.async {
            withAnimation(.timingCurve(0.85, 0.0, 0.2, 1.0, duration: 0.9)) {
                displayedSnapshots = targetDisplaySnapshots
                fitFullDomain()
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
        let values = visibleSnapshots.map(\.value)

        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1

        let range = maxValue - minValue

        let paddingBottom = range * 0.13   // 👈 下方留15%空间
        let paddingTop = range * 0.15

        let yMin = minValue - paddingBottom
        let yMax = maxValue + paddingTop

        return yMin...yMax
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

    private func semanticDateKey(for displayIndex: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        return formatter.string(from: semanticSnapshot(for: displayIndex).date)
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
