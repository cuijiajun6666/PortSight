//
//  ContentView.swift
//  PortSight
//
//  Created by Chris Cui on 28/4/2026.
//

import SwiftUI
import SwiftData
import Combine
import PortSightKit


struct ContentView: View {
    @StateObject private var demo = PortfolioDemo()
    @StateObject private var terminal = TerminalDemo()
    @State private var morePath: [MoreRoute] = []
    @State private var assetPage: AssetPage = .overview
    @State private var tradingPage: TradingPage = .live
    @StateObject var vm = AssetViewModel()
    @StateObject private var marketVM = MarketStatusViewModel()
    @StateObject private var marketAccessoryVM = IntradayPriceViewModel()
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @Namespace private var animation
    @State var isExpanded: Bool = false
    @State private var selectedTab = 10
    @State private var selectedMarketIndex = 0
    /// True for a moment after launch while 交易 · 实时 is drawn unseen (TradingWarmUp).
    @State private var warmsTrading = false
    /// Looking up a tapped push among the notices; a newer tap replaces it.
    @State private var pushLookup: Task<Void, Never>?

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        
        TabView(selection: $selectedTab) {
            // Plan §0.1: 总览 · 资产 · 交易 · 服务器 · 更多. Holdings, activity and analysis are pages of 资产.
            Tab("总览", systemImage: "square.grid.2x2.fill", value: 10) {
                TerminalOverviewView(selectedTab: $selectedTab)
            }

            Tab("资产", systemImage: "chart.pie.fill", value: 0) {
                AssetsTabView(selectedTab: $selectedTab, page: $assetPage)
            }

            Tab("交易", systemImage: "arrow.left.arrow.right.circle.fill", value: 5) {
                TradingTabView(page: $tradingPage)
            }

            Tab("服务器", systemImage: "server.rack", value: 4) {
                ServerView()
            }

            Tab("更多", systemImage: "ellipsis.circle", value: 6) {
                TerminalMoreView(path: $morePath)
            }

        }
        //.tint(Color(red: 140/255, green: 194/255, blue: 250/255))
        .tabBarMinimizeBehavior(.onScrollDown)
        // The soft, light scroll-edge blur under every navigation bar (same as the family edition).
        .portSightScrollEdge()
        .sensoryFeedback(.selection, trigger: selectedTab)
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
        .onReceive(NotificationCenter.default.publisher(for: .portSightOpenServer)) { _ in
            selectedTab = 4                                     // a tapped notification that is not a relay push
        }
        // A tapped relay push. Its event_id may be a notice id (量化保护检查 …): that notice's page opens, or 总览's
        // IBKR banner for a re-authorization notice. Anything else is an alert and opens as before.
        .onChange(of: PushRoute.shared.pending, initial: true) { _, ref in
            guard let ref else { return }
            PushRoute.shared.pending = nil
            pushLookup?.cancel()
            pushLookup = Task { await openPush(ref) }
        }
        // A notice's button (RelayLink): close what covers the tabs, then show the tab and page it names.
        .onChange(of: NoticeLinkRoute.shared.pending, initial: true) { _, link in
            guard let link else { return }
            NoticeLinkRoute.shared.pending = nil
            open(link)
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == 5 { TradingWarmUp.done = true }   // opened for real: nothing left to warm up
            // The dashboard's holdings link still asks for the old Positions tab (1): it is a page of 资产 now.
            if tab == 1 {
                assetPage = .positions
                selectedTab = 0
                return
            }
            guard !isPreview else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        // 交易 · 实时's feed takes most of a second to build: start it in the background soon after launch. Once it
        // is ready, draw the page once unseen (TradingWarmUp), so opening 交易 the first time does not stall.
        .task {
            guard !isPreview, !TradingWarmUp.done else { return }
            try? await Task.sleep(for: .seconds(1))
            LiveFeed.prepare()
            _ = await LiveFeed.shared()
            guard !Task.isCancelled, !TradingWarmUp.done, selectedTab != 5 else { return }
            TradingWarmUp.done = true
            warmsTrading = true
            try? await Task.sleep(for: .milliseconds(500))
            warmsTrading = false
        }
        .background {
            if warmsTrading { TradingWarmUp() }
        }
        .task {
            if DemoPortfolioData.enabled {
                // The built-in index curve, paired or not (the relay has no index prices yet).
                marketAccessoryVM.loadDemo(symbol: "IXIC")
                marketVM.applyClock()
                return
            }
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
            // The session follows the clock in demo mode: nothing to re-fetch when it opens.
            if DemoPortfolioData.enabled { return }
            guard oldSession != .regular, newSession == .regular else { return }
            marketAccessoryVM.resetForOpenSession(symbol: "IXIC")
        }
        // Pairing (or unpairing) switches every page between the built-in portfolio and the real data mixed with it
        // (Portfolio.isLive reads ServerStore, which PortfolioDemo does not publish): redraw the pages that use
        // `demo`, and reload the NASDAQ accessory's built-in curve. @Published sends before the new value is stored,
        // so this runs on the next turn of the main queue, when RelayNotices.usesRelay reads it.
        .onReceive(
            ServerStore.shared.$pairingState.combineLatest(ServerStore.shared.$isSample)
                .map { pairing, sample in pairing != .unpaired && !sample }
                .removeDuplicates()
                .dropFirst()
        ) { _ in
            DispatchQueue.main.async {
                demo.objectWillChange.send()
                if DemoPortfolioData.enabled {
                    marketAccessoryVM.loadDemo(symbol: "IXIC")
                    selectedMarketIndex = 0
                }
            }
        }
        .onDisappear {
            marketVM.stopPolling()
            marketAccessoryVM.stop()
        }
        .environmentObject(marketVM)
        .environmentObject(demo)
        .environmentObject(terminal)
        .sheet(isPresented: $demo.showNotifications) {
            TerminalMessageCenterView().environmentObject(demo).environmentObject(terminal)
        }
        .sheet(isPresented: $demo.showSettings) {
            名字待定2()
        }

    }

    // MARK: Tapped pushes and notice links

    /// A notice push opens the notice (looked up in /notices, read once more when it is not there yet); a trade
    /// notice also reads the IBKR account at once. Anything else is a relay alert.
    private func openPush(_ ref: PushEventRef) async {
        // Not known yet as a notice or an alert: /notices is read first. 消息中心 opens at once meanwhile, so the tap
        // is answered right away; the page is pushed into it when the lookup is done.
        let id = ref.eventID ?? ""
        let known = RelayNotices.notice(id: id) != nil || ServerStore.shared.knowsEvent(id) || !RelayNotices.usesRelay
        if !known, PushRoute.modalDepth() == 0, !PushRoute.shared.messageCenterOnScreen, !demo.showNotifications {
            demo.showNotifications = true
        }
        guard let notice = await RelayNotices.notice(for: ref) else {
            guard !Task.isCancelled else { return }
            show(.event(ref))
            return
        }
        guard !Task.isCancelled else { return }
        if notice.isTrade { Task { await IBKRStore.shared.nudge() } }
        demo.read.insert(notice.id)
        if notice.isIBKRReauth {
            // The banner is what this notice asks for: 总览 with the banner up, not another page.
            NoticeLinkRoute.shared.open(.ibkrReauth)
        } else {
            show(.notice(notice))
        }
    }

    /// 消息中心 shows the page when it is the screen in front, or opens on it when nothing is presented; any other
    /// sheet or cover would block 消息中心, so then the page goes on top.
    private func show(_ target: PushTarget) {
        let route = PushRoute.shared
        let depth = PushRoute.modalDepth()
        if depth == 1 && route.messageCenterOnScreen {
            route.forMessageCenter = target
        } else if depth == 0 && !route.messageCenterOnScreen {
            route.forMessageCenter = target
            if demo.showNotifications {
                // Asked for earlier behind another sheet and never shown: ask again so it comes up now.
                demo.showNotifications = false
                DispatchQueue.main.async { demo.showNotifications = true }
            } else {
                demo.showNotifications = true
            }
        } else {
            route.forMessageCenter = nil
            PushRoute.presentOverTop(target, demo: demo, terminal: terminal, container: modelContext.container)
        }
    }

    /// Where a notice's link leads. 消息中心 (and anything above it) closes through its binding; a notice page put
    /// over another screen by presentOverTop is closed directly.
    private func open(_ link: RelayLink) {
        if !PushRoute.shared.messageCenterOnScreen { PushRoute.dismissOverTop() }
        demo.showNotifications = false
        // Anything else covering the tabs would hide where the link leads.
        demo.showSettings = false
        isExpanded = false
        switch link {
        case .ibkrReauth:
            selectedTab = 10
            Task { await IBKRStore.shared.refreshStatus(force: true) }
        case .hostDailyReport:
            // The Mac mini's daily ops report has no page of its own: the 服务器 tab shows /host.
            selectedTab = 4
        case .lineReport:
            tradingPage = .reports
            selectedTab = 5
        case .journal:
            tradingPage = .journal
            selectedTab = 5
        case .asset:
            // Reached only when the app has no page for that symbol (DemoNoticeDetail pushes the page otherwise).
            assetPage = .overview
            selectedTab = 0
        }
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
            .offset(x: -CGFloat(min(selectedMarketIndex, marketItems.count - 1)) * width + dragOffset)
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
