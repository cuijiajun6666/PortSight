import SwiftUI
import PortSightKit

struct DemoScopeMenu: View {
    @EnvironmentObject private var demo: PortfolioDemo
    var body: some View {
        Menu {
            Picker("资产范围", selection: $demo.scope) {
                ForEach(PortfolioScope.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            HStack(spacing: 5) {
                Text(demo.scope.rawValue).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
        }.accessibilityLabel("资产范围：" + demo.scope.rawValue)
    }
}
/// 全部 ⌄ as the page's large title, with the market session and connection under it.
struct DemoScopeHeader: View {
    @EnvironmentObject private var demo: PortfolioDemo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                Picker("资产范围", selection: $demo.scope) {
                    ForEach(PortfolioScope.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(demo.scope.rawValue).font(.title.bold()).contentTransition(.interpolate)
                    Image(systemName: "chevron.down").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
            }
            .accessibilityLabel("资产范围：" + demo.scope.rawValue)
            MarketStatusLine()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 15)
    }
}

/// The US session (from the New York clock, MarketClock) and the connection, under the large title of 总览, 资产
/// and 交易.
struct MarketStatusLine: View {
    var body: some View {
        // Re-read every minute, so 盘前 → 盘中 → 盘后 change on their own.
        TimelineView(.everyMinute) { context in
            let market = MarketClock.session(at: context.date)
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    MarketSessionIndicator(session: market.session)
                    Text(market.title)
                }
                HStack(spacing: 5) {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text("已连接")
                }
            }
            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// No longer shown: once paired every page shows real data where the relay has it and the built-in data everywhere
/// else, so nothing is 「尚未接入」. Kept only until no page refers to it any more; do not use it in new code.
enum LiveNote {
    static let quant = "量化账户数据尚未接入"
    static let history = "资产走势尚未接入"
    static let activity = "交易记录尚未接入"
    static let orders = "订单记录尚未接入"
    static let prices = "行情走势尚未接入"
    static let backtest = "回测结果尚未接入"
}

/// 「—」 only where a figure cannot be computed (a percentage of 0, an open order without a price yet), never for a
/// figure the built-in data has.
let missingFigure = "—"

extension PortfolioDemo {
    /// Changes whenever the current scope's real figures change (the IBKR account read again once paired), so pages
    /// that copy them into their own view models (applyDemo) copy them again. Constant before pairing.
    var figuresKey: String {
        guard isLive else { return "" }
        let figures = [total, cash, pnl, dayPnL].map { String($0) }
        let lots = holdings.map { "\($0.symbol):\($0.quantity):\($0.cost):\($0.price):\($0.previous)" }
        return (figures + lots).joined(separator: "|")
    }
}

struct DemoToolbar: ToolbarContent {
    @EnvironmentObject private var demo: PortfolioDemo
    @EnvironmentObject private var terminal: TerminalDemo
    @Environment(\.pageMenu) private var pageMenu
    /// Pages that do not split money by 个人 / 量化 leave the 全部 ⌄ menu out.
    var showsScope = true
    /// false when the page puts its own item just left of the bell: it then adds that item and
    /// `MessageCenterToolbar()` itself, after this (交易 · 实时 does, for its 账户 menu).
    var showsBell = true
    var body: some ToolbarContent {
        // Photos-style large title on the leading side (PortSightNavigationHeader): 全部 ⌄ where money is
        // split by scope, otherwise the page menu (复盘 ⌄ …) when the tab has pages.
        if showsScope {
            ToolbarItem(placement: .subtitle) { DemoScopeHeader() }
            // The title is taken, so the page menu (概览 ⌄ …) sits on the trailing side by the bell.
            if let pageMenu {
                ToolbarItem(placement: .topBarTrailing) { PageMenu(model: pageMenu).padding(.horizontal, 6) }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
        } else if let pageMenu {
            // Same title block as 全部 ⌄, so 复盘 ⌄ sits in exactly the same place.
            ToolbarItem(placement: .subtitle) {
                VStack(alignment: .leading, spacing: 4) {
                    Menu {
                        Picker(pageMenu.name, selection: pageMenu.selection) {
                            ForEach(pageMenu.titles, id: \.self) { Text($0).tag($0) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(pageMenu.selection.wrappedValue).font(.title.bold()).contentTransition(.interpolate)
                            Image(systemName: "chevron.down").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                    }
                    .accessibilityLabel(pageMenu.name + "：" + pageMenu.selection.wrappedValue)
                    MarketStatusLine()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 15)
            }
        }
        // 订单, just left of the bell, on every 资产 page (概览 / 持仓 / 动态 / 分析).
        if pageMenu?.name == "资产页面" {
            ToolbarItem(placement: .topBarTrailing) { OrdersToolbarButton() }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
        if showsBell {
            MessageCenterToolbar()
        }
    }
}

/// Opens the 订单 page in the current page's navigation stack (set by `.ordersDestination()`). Equal for the same
/// page, so setting it again does not redraw what reads it.
struct OpenOrdersAction: Equatable {
    let page: UUID
    let open: () -> Void

    func callAsFunction() { open() }

    static func == (lhs: OpenOrdersAction, rhs: OpenOrdersAction) -> Bool { lhs.page == rhs.page }
}

extension EnvironmentValues {
    @Entry var openOrders: OpenOrdersAction? = nil
}

extension View {
    /// The 订单 page for the toolbar's 订单 button, pushed in this page's NavigationStack. Apply it outside
    /// `.toolbar { DemoToolbar() }` (and inside the NavigationStack).
    ///
    /// A NavigationLink inside the toolbar stops pushing once the page's search field has been used (the search
    /// rebuilds the toolbar): 订单 then did nothing on 动态 and 持仓. A button that sets this page's own
    /// navigationDestination keeps working.
    func ordersDestination() -> some View { modifier(OrdersDestination()) }
}

private struct OrdersDestination: ViewModifier {
    @EnvironmentObject private var demo: PortfolioDemo
    @State private var showsOrders = false
    @State private var page = UUID()

    func body(content: Content) -> some View {
        let shows = $showsOrders
        content
            .environment(\.openOrders, OpenOrdersAction(page: page) { shows.wrappedValue = true })
            .navigationDestination(isPresented: $showsOrders) { OrdersView(orders: demo.orders) }
    }
}

/// The toolbar's 订单 button: the page's `.ordersDestination()` when it has one, else a plain link.
private struct OrdersToolbarButton: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @Environment(\.openOrders) private var openOrders

    var body: some View {
        if let openOrders {
            Button { openOrders() } label: { label }
        } else {
            NavigationLink { OrdersView(orders: demo.orders) } label: { label }
        }
    }

    private var label: some View {
        Label("订单", systemImage: "chart.line.text.clipboard")
    }
}

/// Kept last in each page's trailing toolbar so the bell has one consistent position.
struct MessageCenterToolbar: ToolbarContent {
    @EnvironmentObject private var demo: PortfolioDemo
    @EnvironmentObject private var terminal: TerminalDemo

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            let unread = MessageCenter.unreadCount(demo: demo, terminal: terminal)
            Button { demo.showNotifications = true } label: {
                Image(systemName: "bell")
            }
            // The system's toolbar badge (iOS 26): drawn above the glass, so an animation never clips it.
            .badge(unread)
            .accessibilityLabel("消息中心")
            .accessibilityValue("\(unread) 条未读")
        }
    }
}
