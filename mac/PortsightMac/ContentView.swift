import SwiftUI
import AppKit
import SwiftData
import PortSightKit

struct ContentView: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @EnvironmentObject private var router: DesktopRouter
    @StateObject private var market = MarketStatusViewModel()
    @EnvironmentObject private var terminal: TerminalDemo
    @EnvironmentObject private var uploads: PhotoUploadQueue
    @State private var section: DesktopSection = .overview
    /// Each section remembers its last tab.
    @State private var tabs: [DesktopSection: DesktopTab] = [:]
    @State private var sheet: DesktopSheet?
    @State private var selectedAsset: PortfolioAsset?
    /// The relay event of a clicked push, shown over the bell panel.
    @State private var pushedEvent: PushEventRef?
    /// The notice a clicked push named (its event_id is a notice id, e.g. "protect:2026-11-11:…").
    @State private var pushedNotice: DemoNotice?
    /// Looks up a clicked push's notice; a newer click cancels it.
    @State private var pushRoute: Task<Void, Never>?
    /// The app is in front: the relay is polled only then (desktopAppActive).
    @State private var appActive = NSApplication.shared.isActive
    /// Grows to close every sheet in the window before a push's event is shown (closesForPush).
    @State private var closeSheetsEpoch = 0
    /// The 实时 page's feed outlives section switches (it pauses while the page is off screen).
    @State private var liveStore = DesktopLiveStore()
    /// Line that 交易 · 线路 scrolls to when opened from a 总览 strategy row; cleared once the user leaves that page.
    @State private var lineFocus: String?
    @AppStorage("desktop_appearance") private var appearance = "system"

    private var currentTab: DesktopTab? { tabs[section] ?? section.defaultTab }

    /// Pages laid out as cards, which sit straight on the window glass.
    private var showsCardGrid: Bool { currentTab?.isCardPage ?? false }

    private var tabBinding: Binding<DesktopTab> {
        Binding(get: { currentTab ?? .allAssets }, set: { tabs[section] = $0 })
    }

    private func open(_ page: DesktopPage) { open(DesktopTab(page: page)) }

    private func takeRoute() {
        switch router.take() {
        case .notifications: demo.showNotifications = true
        case .event(let ref):
            // A window shows one sheet at a time: close them all (here and in the pages, the bell panel and an
            // earlier push's page), then show this event once they are gone.
            closeAllSheets()
            pushRoute?.cancel()
            pushRoute = Task { await show(ref) }
        case .section(let target): section = target
        case nil: break
        }
    }

    private func updateActive() {
        let app = NSApplication.shared
        appActive = app.isActive && app.windows.contains {
            $0.canBecomeMain && $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)
        }
    }

    private func closeAllSheets() {
        sheet = nil
        selectedAsset = nil
        pushedEvent = nil
        pushedNotice = nil
        closeSheetsEpoch += 1
    }

    /// A clicked push. Quant protection pushes and the like carry a notice id: that notice's page over the bell panel
    /// (an IBKR re-authorization goes to 总览's banner instead). Anything else keeps the alert page
    /// (DesktopServerEventDetail), which looks the event up in /alerts.
    private func show(_ ref: PushEventRef) async {
        let started = ContinuousClock.now
        // The bell opens at once, so the click is answered while /notices is read (when the notice is not here yet);
        // only a notice already known to be the IBKR re-authorization skips it.
        if RelayNotices.notice(id: ref.eventID ?? "")?.isIBKRReauth != true { demo.showNotifications = true }
        let notice = await RelayNotices.notice(for: ref)
        guard !Task.isCancelled else { return }
        if let notice, notice.isIBKRReauth {
            demo.showNotifications = false
            section = .overview
            await IBKRStore.shared.refreshStatus(force: true)
            return
        }
        demo.showNotifications = true
        // The sheets closed above need a moment to go before another one can be shown.
        let left = Duration.milliseconds(400) - (ContinuousClock.now - started)
        if left > .zero { try? await Task.sleep(for: left) }
        guard !Task.isCancelled else { return }
        if let notice {
            pushedNotice = notice.asNotice()
            // A personal trade: the IBKR account (and its status) are read now, not at the next tick.
            if notice.isTrade { await IBKRStore.shared.nudge() }
        } else {
            pushedEvent = ref
        }
    }

    /// A notice's button (RelayLink): close the notice page and go where the link points.
    private func follow(_ link: RelayLink) {
        pushRoute?.cancel()
        closeAllSheets()
        switch link {
        case .ibkrReauth:
            // The banner at the top of 总览 does the re-authorization; read the state now so it is current.
            section = .overview
            Task { await IBKRStore.shared.refreshStatus(force: true) }
        case .hostDailyReport:
            // The Mac mini's daily ops report has no page of its own: the 服务器 page shows what it covers (/host).
            open(DesktopTab.serverStatus)
        case .lineReport:
            open(DesktopTab.reports)
        case .journal:
            open(DesktopTab.journal)
        case .asset(let symbol):
            open(DesktopTab.allAssets)
            // The asset's page when the app has one for that symbol, else 资产 · 概览 alone.
            guard let holding = Portfolio.holding(symbol) else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                selectedAsset = holding.asset
            }
        }
    }

    private func open(_ tab: DesktopTab) {
        tabs[tab.section] = tab
        section = tab.section
    }

    var body: some View {
        HStack(spacing: 0) {
            DesktopSidebar(selection: $section)
            DesktopTrailingPanel(isPresented: demo.showNotifications) {
                // minWidth 0: a page wider than the space left by the bell panel is clipped by the surface
                // instead of pushing under the panel.
                page
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    // Card pages (资产, 交易 · 策略): no white panel under the cards.
                    .modifier(DesktopContentSurface(opaque: !showsCardGrid))
            } panel: {
                DesktopNotificationsPanel()
            }
        }
        // Restores double-click-to-zoom on the toolbar's empty space (see DesktopTitlebarDoubleClick).
        .background { DesktopTitlebarDoubleClick().frame(width: 0, height: 0).accessibilityHidden(true) }
        .toolbar {
            DesktopToolbar(section: section, tab: tabBinding, openNotifications: {
                demo.showNotifications.toggle()
            }, openSettings: { sheet = .settings })
        }
        .toolbar(removing: .title)
        .modifier(DesktopWindowBackground())
        .buttonStyle(.glass)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        .environmentObject(demo).environmentObject(market)
        .sheet(item: $sheet) { destination in
            DesktopSheetContainer(title: destination.title,
                                  width: destination == .settings ? 520 : 850,
                                  height: destination == .settings ? 600 : 720) {
                switch destination {
                case .settings: DesktopSettingsView()
                case .report: DemoReportDetail()
                case .fullAnalysis: AnalysisView()
                case .strategy: DemoStrategyDetail()
                }
            }.environmentObject(demo).environmentObject(market)
        }
        .sheet(item: $selectedAsset) { asset in
            DesktopSheetContainer(title: asset.symbol + " · " + asset.name) {
                AssetDetailView(asset: asset)
            }.environmentObject(demo).environmentObject(market)
        }
        .sheet(item: $pushedEvent) { ref in
            DesktopSheetContainer(title: "告警详情", width: 520, height: 560, showsTitleBar: false) {
                DesktopServerEventDetail(ref: ref)
            }
        }
        .sheet(item: $pushedNotice) { notice in
            DesktopSheetContainer(title: "通知详情", width: 520, height: 560, showsTitleBar: false) {
                DemoNoticeDetail(notice: notice)
            }
            .environmentObject(demo)
            .environment(\.openNoticeLink) { follow($0) }
        }
        .onChange(of: demo.showNotifications) { _, show in
            if show { sheet = nil; selectedAsset = nil }
            // Opening the bell reads /notices (the store keeps reads at least 30 s apart by itself).
            if show, RelayNotices.usesRelay { Task { await RelayNotices.store.load() } }
        }
        // In front means: the app is active and a window of it can be seen (not minimized, not fully covered).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            updateActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            updateActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { _ in updateActive() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { _ in updateActive() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { _ in
            updateActive()
        }
        .onChange(of: demo.showSettings) { _, show in
            if show { sheet = .settings; demo.showSettings = false }
        }
        // The section on screen, while a window of the app can be seen and the app is in front: the relay every 10 s
        // (/host, alerts, notices, the IBKR login state and account, new fills and orders). Sections that show none
        // of it, a minimized or covered window and the app in the background read nothing.
        .task(id: "\(appActive)|\(section.rawValue)") {
            guard appActive, [.overview, .assets, .trading, .server].contains(section) else { return }
            while !Task.isCancelled {
                if RelayNotices.usesRelay { await ServerStore.shared.refresh() }
                try? await Task.sleep(for: .seconds(RelayAPI.minRefreshInterval))
            }
        }
        // The US session from the New York clock (盘前 / 盘中 / 盘后 / 夜盘 / 休市), kept current while the window is open.
        .task {
            while !Task.isCancelled {
                market.applyClock()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        // 交易 · 实时's feed takes most of a second to build: start it in the background soon after launch, paired or
        // not (the page shows the built-in feed either way).
        .task {
            try? await Task.sleep(for: .seconds(1))
            LiveFeed.prepare()
        }
        // Menu bar requests wait in the router, so they also apply to a window opened by the request.
        .onAppear(perform: takeRoute)
        .onChange(of: router.pending) { _, _ in takeRoute() }
        .onChange(of: section == .trading && currentTab == .lines) { _, onLines in
            if !onLines { lineFocus = nil }
        }
        .environment(\.desktopSection, section)
        .environment(\.closeSheetsEpoch, closeSheetsEpoch)
        .environment(\.desktopAppActive, appActive)
        .environment(\.openNoticeLink) { follow($0) }
        // Upload is a page of 云盘, so it resizes with the window like every other page.
        .environment(\.openPhotoUploader) { open(.upload) }
    }

    @ViewBuilder private var page: some View {
        switch section {
        case .overview:
            DesktopTerminalOverview(open: { section = $0 }, openLine: { id in
                lineFocus = id
                open(DesktopTab.lines)
            })
        case .remote: DesktopRemoteView()
        case .backtest: DesktopBacktestView()
        default:
            switch currentTab ?? .allAssets {
            case .allAssets:
                DesktopDashboard(openPage: { open($0) }, openSheet: { sheet = $0 }, openAsset: { selectedAsset = $0 })
            case .usStocks:
                DesktopPositionsView(assetClass: .usStocks, openAsset: { selectedAsset = $0 }).id(DesktopTab.usStocks)
            case .crypto:
                DesktopPositionsView(assetClass: .crypto, openAsset: { selectedAsset = $0 }).id(DesktopTab.crypto)
            case .positions:
                DesktopPositionsView(openAsset: { selectedAsset = $0 }).id(DesktopTab.positions)
            case .orders: DesktopOrdersView()
            case .market: DesktopMarketView()
            case .analysis: DesktopAnalysisView(openSheet: { sheet = $0 })
            case .activity: DesktopActivityView()
            case .live: DesktopLivePage(store: liveStore)
            case .journal: DesktopJournalPage()
            case .lines: DesktopTradingLinesView(initialLineID: lineFocus)
            case .reports: DesktopTradingReportsView()
            case .strategies: DesktopStrategiesView()
            case .backtest: DesktopBacktestView()
            case .serverStatus: DesktopServerOverview()
            case .heartbeats: DesktopHeartbeatsView()
            case .jobs: DesktopJobsView()
            case .photos: DesktopCloudPhotosView()
            case .upload: DesktopPhotoUploadView(queue: uploads)
            case .storage: DesktopStorageView()
            case .transfer: DesktopTransferView()
            case .aiAsk, .aiDuty, .aiReview: DesktopAIView(tab: currentTab ?? .aiAsk)
            }
        }
    }
}



#Preview {
    ContentView().environmentObject(TerminalDemo()).environmentObject(PhotoUploadQueue())
        .environmentObject(PortfolioDemo()).environmentObject(DesktopRouter()).modelContainer(for: [Item.self, AssetSnapshotRecord.self, StockLogoRecord.self], inMemory: true)
}
