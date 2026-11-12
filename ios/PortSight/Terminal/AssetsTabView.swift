//
//  AssetsTabView.swift
//  PortSight
//
//  资产 tab: the original asset pages (overview dashboard, holdings, activity, analysis) under one tab.
//  Each page is shown exactly as before; only a page menu joins the toolbar row beside 全部 ⌄.
//  The same page menu and kept-alive container are used by the 交易 tab.
//

import SwiftUI
import PortSightKit

enum AssetPage: String, CaseIterable, Identifiable {
    case overview = "概览", positions = "持仓", activity = "动态", analysis = "分析"
    var id: String { rawValue }
}

/// The pages of one tab and the selected one, for the toolbar's page menu.
struct PageMenuModel {
    let name: String
    let titles: [String]
    let selection: Binding<String>

    init<Page: RawRepresentable & CaseIterable & Hashable>(name: String, page: Binding<Page>) where Page.RawValue == String {
        self.name = name
        titles = Page.allCases.map(\.rawValue)
        selection = Binding(get: { page.wrappedValue.rawValue },
                            set: { if let new = Page(rawValue: $0) { page.wrappedValue = new } })
    }
}

private struct PageMenuKey: EnvironmentKey {
    static let defaultValue: PageMenuModel? = nil
}

extension EnvironmentValues {
    /// Set by a tab with several pages; DemoToolbar shows the page menu only when it is present.
    var pageMenu: PageMenuModel? {
        get { self[PageMenuKey.self] }
        set { self[PageMenuKey.self] = newValue }
    }
}

/// Page switcher styled like DemoScopeMenu, so the two read as one row.
struct PageMenu: View {
    let model: PageMenuModel

    var body: some View {
        Menu {
            Picker(model.name, selection: model.selection) {
                ForEach(model.titles, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            HStack(spacing: 5) {
                Text(model.selection.wrappedValue).font(.subheadline.weight(.semibold))
                    .contentTransition(.interpolate)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
        }
        .accessibilityLabel(model.name + "：" + model.selection.wrappedValue)
    }
}

/// Pages are built on first visit and then kept alive, like separate tabs: switching keeps each page's
/// scroll position, filters, pushed details and loaded data. Pages blur-replace into each other.
struct KeptAlivePages<Page: RawRepresentable & CaseIterable & Hashable & Identifiable, Content: View>: View
where Page.RawValue == String, Page.AllCases: RandomAccessCollection {
    let name: String
    @Binding var page: Page
    @ViewBuilder var content: (Page) -> Content
    @State private var visited: Set<Page> = []

    var body: some View {
        ZStack {
            ForEach(Page.allCases) { item in
                if visited.contains(item) || item == page {
                    content(item)
                        // Blur-replace between pages, including each page's own toolbar.
                        .blur(radius: item == page ? 0 : 14)
                        .opacity(item == page ? 1 : 0)
                        .allowsHitTesting(item == page)
                        .accessibilityHidden(item != page)
                }
            }
        }
        .animation(.smooth(duration: 0.35), value: page)
        .environment(\.pageMenu, PageMenuModel(name: name, page: $page))
        .onAppear { visited.insert(page) }
        .onChange(of: page) { _, new in visited.insert(new) }
    }
}

/// Whether the page this view belongs to is the one in front: its tab selected, its page shown, the app active and
/// no sheet over it. Kept-alive pages stay "on screen" to SwiftUI while hidden, so polling asks this, not onAppear.
/// True where nothing sets it (a page outside the 资产 tab).
extension EnvironmentValues {
    @Entry var pageInFront = true
}

struct AssetsTabView: View {
    @Binding var selectedTab: Int
    @Binding var page: AssetPage
    @EnvironmentObject private var demo: PortfolioDemo
    @Environment(\.scenePhase) private var scenePhase
    /// Pairing and unpairing change RelayNotices.usesRelay.
    @ObservedObject private var server = ServerStore.shared

    var body: some View {
        // Read here so polling follows the tab, the page, the app and the sheets: kept-alive pages stay "on screen"
        // to SwiftUI while hidden and under a sheet.
        let tabInFront = selectedTab == 0 && scenePhase == .active && !demo.showNotifications && !demo.showSettings
        let polls = tabInFront && RelayNotices.usesRelay
        KeptAlivePages(name: "资产页面", page: $page) { item in
            Group {
                switch item {
                case .overview:
                    DashboardView(selectedTab: $selectedTab)
                case .positions:
                    PositionsView()
                case .activity:
                    DemoActivityView()
                case .analysis:
                    // Same wrapper the former Analysis tab used.
                    NavigationStack {
                        AnalysisView()
                            .toolbar { DemoToolbar() }
                            .ordersDestination()
                    }
                }
            }
            .environment(\.pageInFront, tabInFront && item == page)
        }
        // The personal IBKR account (/account and /ibkr/status) every 10 s on every 资产 page while it is in front;
        // the figures on each page follow (demo.figuresKey). Cancelled in the background, under a sheet, on another tab.
        .task(id: polls) {
            guard polls else { return }
            await IBKRStore.shared.runAssetsPolling()
        }
        // 动态 lists the account's activity and 概览's 最近动态 card shows its latest records: brought up to date now,
        // then the heartbeat every 10 s. (The 订单 page runs the same while it is on screen.)
        .task(id: polls && (page == .activity || page == .overview)) {
            guard polls, page == .activity || page == .overview else { return }
            await IBKRActivityStore.shared.runPolling()
        }
    }
}
