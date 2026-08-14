//
//  AllocationDonutChart.swift
//  PortSight
//
//  Created by Chris Cui on 28/4/2026.
//
import SwiftUI
import Charts
import SwiftData

struct AllocationItem: Identifiable {
    let name: String
    let value: Double

    var id: String { name }
}

struct AllocationDonutChart: View {
    let items: [AllocationItem]
    let animationKey: String
    private static var hasPlayedLaunchAnimation = false

    private var total: Double {
        displayedItems.map(\.value).reduce(0, +)
    }
    private var itemSignature: String {
        itemsSignature(displayedItems)
    }
    @State private var animateChart = false
    @State private var displayedItems: [AllocationItem]
    @State private var pendingItems: [AllocationItem]?
    @State private var isLaunchAnimating = false
    @State private var lastAnimationKey: String?
    @State private var pendingAnimation: DispatchWorkItem?

    init(items: [AllocationItem], animationKey: String) {
        self.items = items
        self.animationKey = animationKey
        _displayedItems = State(initialValue: items)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Chart(Array(displayedItems.enumerated()), id: \.offset) { index, item in
                SectorMark(
                    angle: .value("Value", animateChart ? item.value : 0),
                    innerRadius: .ratio(0.62),
                    angularInset: 1
                )
                .foregroundStyle(color(for: index, name: item.name))
                .cornerRadius(5)
            }
            .animation(.timingCurve(0.85, 0.0, 0.2, 1.0, duration: 0.85), value: itemSignature)
            .frame(width: 140, height: 140)
            .chartLegend(.hidden)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(displayedItems.enumerated()), id: \.element.id) { index, item in
                    let percent = total > 0 ? item.value / total * 100 : 0
                    let percentText: String = {
                        if percent < 0.01 {
                            return "<0.01%"
                        } else if percent < 1 {
                            return String(format: "%.2f%%", percent)
                        } else {
                            return String(format: "%.1f%%", percent)
                        }
                    }()

                    HStack(spacing: 8) {
                        Circle()
                            .foregroundStyle(color(for: index, name: item.name))
                            .frame(width: 10, height: 10)

                        Text(item.name)
                            .font(.subheadline)

                        Spacer()

                        Text("$\(item.value, specifier: "%.0f") (\(percentText))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.bottom)
        .onAppear {
            lastAnimationKey = animationKey
            if displayedItems.isEmpty, !items.isEmpty {
                displayedItems = items
            }

            if Self.hasPlayedLaunchAnimation {
                animateChart = true
                applyItemsAfterLaunchIfNeeded(items)
            } else {
                playAnimation()
            }
        }
        .onChange(of: itemsSignature(items)) { _, _ in
            applyItemsAfterLaunchIfNeeded(items)
        }
        .onChange(of: animationKey) { _, newValue in
            guard lastAnimationKey != newValue else { return }
            lastAnimationKey = newValue
            pendingAnimation?.cancel()
            pendingAnimation = nil
            pendingItems = nil
            isLaunchAnimating = false
            animateChart = true
            Self.hasPlayedLaunchAnimation = true
            applyDisplayedItems(items)
        }
        .onDisappear {
            pendingAnimation?.cancel()
            pendingAnimation = nil
            pendingItems = nil
        }
    }
    private func playAnimation() {
        pendingAnimation?.cancel()
        isLaunchAnimating = true
        Self.hasPlayedLaunchAnimation = true
        animateChart = false

        let workItem = DispatchWorkItem {
            withAnimation(.timingCurve(0.85, 0.0, 0.2, 1.0, duration: 1.3)) {
                animateChart = true
            }
        }
        pendingAnimation = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            isLaunchAnimating = false

            if let itemsToApply = pendingItems {
                pendingItems = nil
                applyDisplayedItems(itemsToApply)
            }
        }
    }

    private func applyItemsAfterLaunchIfNeeded(_ newItems: [AllocationItem]) {
        guard !newItems.isEmpty else { return }

        if !Self.hasPlayedLaunchAnimation, displayedItems.isEmpty {
            displayedItems = newItems
            playAnimation()
        } else if isLaunchAnimating {
            pendingItems = newItems
        } else {
            applyDisplayedItems(newItems)
        }
    }

    private func applyDisplayedItems(_ newItems: [AllocationItem]) {
        guard itemsSignature(displayedItems) != itemsSignature(newItems) else { return }

        withAnimation(.timingCurve(0.85, 0.0, 0.2, 1.0, duration: 0.85)) {
            displayedItems = newItems
        }
    }

    private func itemsSignature(_ items: [AllocationItem]) -> String {
        items.map { "\($0.name):\($0.value)" }.joined(separator: "|")
    }
}


struct AllocationWeightBar: View {
    let items: [AllocationItem]
    let animationKey: String
    private static var hasPlayedLaunchAnimation = false

    @State private var animateBar = false
    @State private var displayedItems: [AllocationItem]
    @State private var pendingItems: [AllocationItem]?
    @State private var isLaunchAnimating = false
    @State private var showLegend = true
    @State private var displayedLegendItems: [AllocationItem] = []
    @State private var incomingLegendItems: [AllocationItem] = []
    @State private var showIncomingLegend = false
    @State private var lastAnimationKey: String?
    @State private var pendingAnimation: DispatchWorkItem?
    @State private var pendingLegendAnimation: DispatchWorkItem?

    init(items: [AllocationItem], animationKey: String) {
        self.items = items
        self.animationKey = animationKey
        _displayedItems = State(initialValue: items)
        _displayedLegendItems = State(initialValue: Array(items.prefix(4)))
    }

    private var total: Double {
        displayedItems.map(\.value).reduce(0, +)
    }

    private var itemSignature: String {
        itemsSignature(displayedItems)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    if total > 0 {
                        ForEach(Array(displayedItems.enumerated()), id: \.offset) { index, item in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(color(for: index, name: item.name))
                                .frame(
                                    width: animateBar ? max(proxy.size.width * item.value / total, 2) : 0
                                )
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.secondary.opacity(0.18))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .animation(.timingCurve(0.85, 0.0, 0.2, 1.0, duration: 0.85), value: itemSignature)
            }
            .frame(height: 10)

            ZStack(alignment: .leading) {
                legendRow(items: legendItems)
                    .opacity(showLegend ? 1 : 0)

                if !incomingLegendItems.isEmpty {
                    legendRow(items: incomingLegendItems)
                        .opacity(showIncomingLegend ? 1 : 0)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: showLegend)
            .animation(.easeInOut(duration: 0.22), value: showIncomingLegend)
        }
        .onAppear {
            lastAnimationKey = animationKey
            if displayedItems.isEmpty, !items.isEmpty {
                displayedItems = items
                displayedLegendItems = Array(items.prefix(4))
            }

            if Self.hasPlayedLaunchAnimation {
                animateBar = true
                applyItemsAfterLaunchIfNeeded(items)
            } else {
                playAnimation()
            }
        }
        .onChange(of: itemsSignature(items)) { _, _ in
            applyItemsAfterLaunchIfNeeded(items)
        }
        .onChange(of: animationKey) { _, newValue in
            guard lastAnimationKey != newValue else { return }
            lastAnimationKey = newValue
            pendingAnimation?.cancel()
            pendingAnimation = nil
            pendingItems = nil
            isLaunchAnimating = false
            animateBar = true
            applyDisplayedItems(items)
        }
        .onDisappear {
            pendingAnimation?.cancel()
            pendingAnimation = nil
            pendingLegendAnimation?.cancel()
            pendingLegendAnimation = nil
            pendingItems = nil
        }
    }

    private var legendItems: [AllocationItem] {
        displayedLegendItems.isEmpty ? Array(items.prefix(4)) : displayedLegendItems
    }

    private func legendRow(items: [AllocationItem]) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 5) {
                    Circle()
                        .fill(color(for: index, name: item.name))
                        .frame(width: 7, height: 7)

                    Text(item.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func playLegendTransition(nextItems: [AllocationItem]) {
        pendingLegendAnimation?.cancel()
        incomingLegendItems = nextItems
        showIncomingLegend = false

        withAnimation(.easeInOut(duration: 0.18)) {
            showLegend = false
            showIncomingLegend = true
        }

        let workItem = DispatchWorkItem {
            var transaction = Transaction()
            transaction.disablesAnimations = true

            withTransaction(transaction) {
                displayedLegendItems = nextItems
                showLegend = true
                incomingLegendItems = []
                showIncomingLegend = false
            }
        }

        pendingLegendAnimation = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
    }

    private func playAnimation() {
        pendingAnimation?.cancel()
        isLaunchAnimating = true
        Self.hasPlayedLaunchAnimation = true
        animateBar = false

        let workItem = DispatchWorkItem {
            withAnimation(.timingCurve(0.85, 0.0, 0.2, 1.0, duration: 1.3)) {
                animateBar = true
            }
        }
        pendingAnimation = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            isLaunchAnimating = false

            if let itemsToApply = pendingItems {
                pendingItems = nil
                applyDisplayedItems(itemsToApply)
            }
        }
    }

    private func applyItemsAfterLaunchIfNeeded(_ newItems: [AllocationItem]) {
        guard !newItems.isEmpty else { return }

        if isLaunchAnimating {
            pendingItems = newItems
        } else if displayedItems.isEmpty, !Self.hasPlayedLaunchAnimation {
            displayedItems = newItems
            displayedLegendItems = Array(newItems.prefix(4))
            playAnimation()
        } else {
            applyDisplayedItems(newItems)
        }
    }

    private func applyDisplayedItems(_ newItems: [AllocationItem]) {
        guard itemsSignature(displayedItems) != itemsSignature(newItems) else { return }

        let nextLegendItems = Array(newItems.prefix(4))
        let shouldAnimateLegend = legendSignature(displayedLegendItems) != legendSignature(nextLegendItems)

        withAnimation(.timingCurve(0.85, 0.0, 0.2, 1.0, duration: 0.85)) {
            displayedItems = newItems
        }

        if shouldAnimateLegend {
            playLegendTransition(nextItems: nextLegendItems)
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true

            withTransaction(transaction) {
                displayedLegendItems = nextLegendItems
                incomingLegendItems = []
                showLegend = true
                showIncomingLegend = false
            }
        }
    }

    private func itemsSignature(_ items: [AllocationItem]) -> String {
        items.map { "\($0.name):\($0.value)" }.joined(separator: "|")
    }

    private func legendSignature(_ items: [AllocationItem]) -> String {
        items.map(\.name).joined(separator: "|")
    }
}

func color(for index: Int) -> Color {
    let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan]
    return colors[index % colors.count]
}


func color(for index: Int, name: String) -> Color {
    // Cash → 柔和绿色
    if name.lowercased().contains("cash") {
        return Color.green.opacity(0.5)
    }
    
    // 更柔和的 pastel 配色
    let colors: [Color] = [
        Color.blue.opacity(0.5),
        Color.indigo.opacity(0.5),
        Color.teal.opacity(0.5),
        Color.orange.opacity(0.5),
        Color.purple.opacity(0.5),
        Color.pink.opacity(0.5)
    ]
    
    return colors[index % colors.count]
}

#Preview {
    let items = [
        AllocationItem(name: "股票", value: 45_000),
        AllocationItem(name: "Cash", value: 12_000),
        AllocationItem(name: "ETF", value: 18_000),
        AllocationItem(name: "加密货币", value: 8_000)
    ]

    VStack(spacing: 24) {
        AllocationDonutChart(items: items, animationKey: "preview")
        AllocationWeightBar(items: items, animationKey: "preview")
            .padding()
    }
}
