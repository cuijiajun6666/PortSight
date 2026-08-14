//
//  ContentView.swift
//  PortSight
//
//  Created by Chris Cui on 28/4/2026.
//

import SwiftUI
import SwiftData
import Combine


struct ContentView: View {
    @StateObject var vm = AssetViewModel()
    @StateObject private var marketVM = MarketStatusViewModel()
    @StateObject private var marketAccessoryVM = IntradayPriceViewModel()
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @Namespace private var animation
    @State var isExpanded: Bool = false
    @State private var selectedTab = 0
    @State private var selectedMarketIndex = 0

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "chart.pie.fill", value: 0) {
                DashboardView(selectedTab: $selectedTab)
            }

            Tab("Positions", systemImage: "list.bullet.rectangle", value: 1) {
                PositionsView()
            }

            Tab("Settings", systemImage: "gearshape", value: 3) {
                名字待定2()
                    .tint(Color(red: 140/255, green: 194/255, blue: 250/255))
            }

            Tab("Analysis", systemImage: "apple.intelligence", value: 2, role: .search) {
                AnalysisView()
            }
        }
        //.tint(Color(red: 140/255, green: 194/255, blue: 250/255))
        .tabBarMinimizeBehavior(.onScrollDown)
        //可以提取子识视图
        .tabViewBottomAccessory {
            MarketBottomAccessory(
                symbol: "IXIC",
                title: "NASDAQ",
                selectedMarketIndex: $selectedMarketIndex,
                intradayVM: marketAccessoryVM
            ) {
                isExpanded = true
            }
            //.padding(.horizontal)
            .matchedTransitionSource(id: "MINI", in: animation)
            .contentShape(Capsule())
        }
        .fullScreenCover(isPresented: $isExpanded) {
            ScrollView {
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                MarketView()
                    .navigationTransition(.zoom(sourceID: "MINI", in: animation))
            }
            // To Avoid Transparency!
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        }
        .onChange(of: selectedTab) { _, _ in
            guard !isPreview else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        .task {
            marketAccessoryVM.loadCache(symbol: "IXIC")

            if isPreview {
                await marketAccessoryVM.fetch(symbol: "IXIC")
                return
            }

            Task(priority: .utility) {
                await DealsViewModel.prewarmCacheIfNeeded()
                await OpenOrdersViewModel.prewarmCacheIfNeeded()
            }

            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }

            marketVM.startPolling(every: 20)
            marketAccessoryVM.start(symbol: "IXIC")
        }
        .onChange(of: marketVM.session) { oldSession, newSession in
            guard oldSession != .regular, newSession == .regular else { return }
            marketAccessoryVM.resetForOpenSession(symbol: "IXIC")
        }
        .onDisappear {
            marketVM.stopPolling()
            marketAccessoryVM.stop()
        }
        .environmentObject(marketVM)

    }
}

struct MarketBottomAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var dragOffset: CGFloat = 0
    @State private var didTriggerUpwardOpen = false

    let symbol: String
    let title: String

    @Binding var selectedMarketIndex: Int
    @ObservedObject var intradayVM: IntradayPriceViewModel
    let onOpen: () -> Void

    private struct MarketAccessoryItem: Identifiable {
        let id: Int
        let title: String
        let price: Double
        let change: Double
        let changePercent: Double
        let points: [IntradayPricePoint]
        let isLoading: Bool

        var color: Color {
            change >= 0 ? .green : .red
        }
    }

    private static let dowPlaceholderPoints = placeholderPoints(
        code: "US.DJI",
        base: 39284.42,
        offsets: [-36, -18, -44, -20, -28, -62, -51, -86]
    )

    private static let spPlaceholderPoints = placeholderPoints(
        code: "US.SPX",
        base: 5314.11,
        offsets: [-28, -12, -20, 6, 12, 19, 15, 25]
    )

    private var price: Double {
        intradayVM.summary?.price ?? intradayVM.points.last?.curPrice ?? 0
    }

    private var change: Double {
        intradayVM.summary?.change ?? fallbackChange
    }

    private var changePercent: Double {
        intradayVM.summary?.changePercent ?? fallbackChangePercent
    }

    private var fallbackChange: Double {
        guard let latestPoint = intradayVM.points.last,
              let lastClose = latestPoint.lastClose else {
            return 0
        }

        return latestPoint.curPrice - lastClose
    }

    private var fallbackChangePercent: Double {
        guard let lastClose = intradayVM.points.last?.lastClose,
              lastClose > 0 else {
            return 0
        }

        return fallbackChange / lastClose * 100
    }

    private var marketItems: [MarketAccessoryItem] {
        [
            MarketAccessoryItem(
                id: 0,
                title: title,
                price: price,
                change: change,
                changePercent: changePercent,
                points: intradayVM.points,
                isLoading: intradayVM.isLoading
            ),
            MarketAccessoryItem(
                id: 1,
                title: "DOW",
                price: 39284.42,
                change: -86.12,
                changePercent: -0.22,
                points: Self.dowPlaceholderPoints,
                isLoading: false
            ),
            MarketAccessoryItem(
                id: 2,
                title: "S&P",
                price: 5314.11,
                change: 24.68,
                changePercent: 0.47,
                points: Self.spPlaceholderPoints,
                isLoading: false
            )
        ]
    }

    private var chartWidth: CGFloat {
        switch placement {
        case .inline:
            75
        case .expanded, .none:
            100
        @unknown default:
            70
        }
    }

    private var chartMaximumPointCount: Int {
        switch placement {
        case .inline:
            32
        case .expanded, .none:
            64
        @unknown default:
            32
        }
    }

    private var pagerSettleAnimation: Animation {
        .interactiveSpring(response: 0.46, dampingFraction: 0.9, blendDuration: 0.08)
    }

    private static func placeholderPoints(code: String, base: Double, offsets: [Double]) -> [IntradayPricePoint] {
        offsets.enumerated().map { index, offset in
            IntradayPricePoint(
                code: code,
                name: nil,
                time: String(format: "2026-05-28 09:%02d:00", 30 + index * 5),
                isBlank: false,
                openedMins: 570 + index * 5,
                curPrice: base + offset,
                lastClose: base,
                avgPrice: nil,
                volume: nil,
                turnover: nil
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)

            HStack(spacing: 0) {
                ForEach(marketItems) { item in
                    HStack {
                        marketRow(item: item, chartWidth: chartWidth)
                        Spacer()
                    }
                    .frame(width: width, height: proxy.size.height, alignment: .center)
                }
            }
            .frame(height: proxy.size.height, alignment: .center)
            .offset(x: -CGFloat(selectedMarketIndex) * width + dragOffset)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleGestureChanged(value, width: width)
                    }
                    .onEnded { value in
                        handleGestureEnd(value, width: width)
                    }
            )
            .animation(
                pagerSettleAnimation,
                value: selectedMarketIndex
            )
            .animation(
                pagerSettleAnimation,
                value: dragOffset == 0
            )
        }
        .frame(height: 44)
        .clipped()
        .contentShape(Rectangle())
    }

    private func handleGestureChanged(_ value: DragGesture.Value, width: CGFloat) {
        let translation = value.translation
        let shouldOpen =
            translation.height < -34 &&
            abs(translation.height) > abs(translation.width) * 1.15

        if shouldOpen && !didTriggerUpwardOpen {
            didTriggerUpwardOpen = true
            dragOffset = 0
            onOpen()
            return
        }

        guard !didTriggerUpwardOpen else { return }

        dragOffset = boundedDragOffset(
            translation.width,
            width: width
        )
    }

    private func boundedDragOffset(_ offset: CGFloat, width: CGFloat) -> CGFloat {
        let isAtFirst = selectedMarketIndex == 0
        let isAtLast = selectedMarketIndex == marketItems.count - 1

        if (isAtFirst && offset > 0) || (isAtLast && offset < 0) {
            return offset * 0.28
        }

        return offset
    }

    private func handleGestureEnd(_ value: DragGesture.Value, width: CGFloat) {
        guard !didTriggerUpwardOpen else {
            didTriggerUpwardOpen = false
            dragOffset = 0
            return
        }

        let translation = value.translation
        let distance = hypot(translation.width, translation.height)

        guard distance > 8 else {
            dragOffset = 0
            onOpen()
            return
        }

        settleDrag(
            translation: translation.width,
            predictedTranslation: value.predictedEndTranslation.width,
            width: width
        )
    }

    private func settleDrag(
        translation: CGFloat,
        predictedTranslation: CGFloat,
        width: CGFloat
    ) {
        let threshold = width * 0.4
        let referenceTranslation = abs(predictedTranslation) > abs(translation)
            ? predictedTranslation
            : translation

        guard abs(referenceTranslation) > threshold else {
            withAnimation(pagerSettleAnimation) {
                dragOffset = 0
            }
            return
        }

        if referenceTranslation < 0 {
            guard selectedMarketIndex < marketItems.count - 1 else {
                withAnimation(pagerSettleAnimation) {
                    dragOffset = 0
                }
                return
            }

            withAnimation(pagerSettleAnimation) {
                selectedMarketIndex += 1
                dragOffset = 0
            }
        } else {
            guard selectedMarketIndex > 0 else {
                withAnimation(pagerSettleAnimation) {
                    dragOffset = 0
                }
                return
            }

            withAnimation(pagerSettleAnimation) {
                selectedMarketIndex -= 1
                dragOffset = 0
            }
        }
    }

    private func marketRow(item: MarketAccessoryItem, chartWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("\(item.title): ")
                        .fontWeight(.bold)
                        .font(.subheadline)

                    Text("\(item.price, specifier: "%.2f")")
                        .fontWeight(.bold)
                        .font(.subheadline)
                        .foregroundStyle(item.color)
                        .contentTransition(.numericText())
                        .animation(.easeInOut, value: item.price)
                }
                

                HStack(spacing: 5) {
                    Text("\(item.change >= 0 ? "+" : "")\(item.change, specifier: "%.2f")")
                    Text("(\(item.changePercent >= 0 ? "+" : "")\(item.changePercent, specifier: "%.2f")%)")
                }
                .font(.system(size: 12))
                .fontWeight(.bold)
                .foregroundStyle(item.color)
                .contentTransition(.numericText())
                .animation(.easeInOut, value: item.change)
            }
            .lineLimit(1)
            .layoutPriority(1)

            Spacer()

            IntradaySparklineChart(
                points: item.points,
                height: 36,
                maximumPointCount: chartMaximumPointCount,
                tintColor: item.color
            )
            .frame(width: chartWidth)
            .padding(.trailing, 5)
            .overlay {
                if item.points.isEmpty && item.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        }
        .padding(.leading)
    }

}

#Preview {
    ContentView()
        .modelContainer(for: [Item.self, AssetSnapshotRecord.self, StockLogoRecord.self], inMemory: true)
}
