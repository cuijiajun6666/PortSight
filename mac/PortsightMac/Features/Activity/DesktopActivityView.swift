import SwiftUI
import PortSightKit

/// 动态. Before pairing: the built-in timeline (unchanged). Once paired: the personal IBKR account's fills, orders
/// (each folded into one line with its status changes and fills), position changes and cash movements, by day
/// (IBKRActivityStore), polled through the heartbeat while this page is on screen and the app is in front; the
/// built-in quant (and shared) rows follow under 量化账户 in 全部, and 量化 shows them as before pairing. While the
/// IBKR account has no record at all, the built-in personal rows stand in (Portfolio.activities).
struct DesktopActivityView: View {
    @EnvironmentObject private var demo: PortfolioDemo
    /// Pairing or unpairing turns the page live or back (demo.isLive reads this store).
    @ObservedObject private var server = ServerStore.shared
    @Environment(\.desktopAppActive) private var appActive
    @State private var filter = "全部"
    @State private var liveFilter: IBKRActivityFilter = .all
    @State private var search = ""
    @State private var selected: DemoActivity?
    @State private var selectedEntry: DesktopIBKRSelection?
    private var query: String { search.trimmingCharacters(in: .whitespaces) }
    private var items: [DemoActivity] {
        demo.activities.filter {
            (filter == "全部" || $0.category == filter)
                && (query.isEmpty || ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(query))
        }
    }
    private var searching: Bool { !query.isEmpty }
    /// The IBKR account's own records are listed: paired, a scope with the personal account, and at least one record.
    private var showsIBKR: Bool {
        demo.isLive && demo.scope != .quant && !IBKRActivityStore.shared.items.isEmpty
    }
    /// The built-in rows listed with the IBKR timeline (全部: the quant and shared ones), by the IBKR type picker
    /// (交易 → 成交, 资金 → 资金 and 分红, 持仓 → none) and the search.
    private var builtInRows: [DemoActivity] {
        let builtIn = Set(DemoPortfolioData.activities.map(\.id))
        return demo.activities.filter { item in
            guard builtIn.contains(item.id) else { return false }
            let kind: Bool = switch liveFilter {
            case .all: true
            case .trades: item.category == "成交"
            case .cash: item.category == "资金" || item.category == "分红"
            case .positions: false
            }
            return kind && (query.isEmpty || (item.title + " " + item.detail).localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        let live = showsIBKR
        DesktopPageScrollView {
            VStack(spacing: 20) {
                DesktopCard {
                    HStack {
                        DesktopSectionTitle(title: "账户时间线",
                                            subtitle: live ? "成交、委托、资金与持仓变化" : "成交、入金、分红与策略事件")
                        Spacer()
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("搜索动态", text: $search).textFieldStyle(.plain)
                                .accessibilityIdentifier("activity_search")
                            if !search.isEmpty {
                                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                                    .buttonStyle(.plain).help("清除搜索")
                            }
                        }.padding(9).frame(width: 190).background(DesktopTheme.canvas, in: RoundedRectangle(cornerRadius: 9))
                        if live {
                            DesktopCapsulePicker(title: "动态类型", options: IBKRActivityFilter.allCases, selection: $liveFilter) { $0.rawValue }
                        } else {
                            DesktopCapsulePicker(title: "动态类型", options: ["全部", "成交", "资金", "分红", "系统"], selection: $filter) { $0 }
                        }
                    }
                }
                if live {
                    liveContent
                } else {
                    sampleCard(items)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if live, let saved = DesktopIBKRText.savedNote(IBKRActivityStore.shared) {
                        Text(saved)
                    }
                    Text("入金和内部划转不计入投资收益。")
                }
                .font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            // Once paired the list follows the search and the type with an animation (the built-in page as before).
            .animation(live ? .smooth : nil, value: search)
            .animation(live ? .smooth : nil, value: liveFilter)
        }.scrollIndicators(.hidden)
            .closesForPush($selected)
            .sheet(item: $selected) { item in
                DesktopSheetContainer(title: "动态详情") { DemoActivityDetail(item: item) }
            }
            .closesForPush($selectedEntry)
            .sheet(item: $selectedEntry) { selection in
                DesktopSheetContainer(title: selection.title) { DesktopIBKREntryDetail(entry: selection.entry) }
            }
            // Only while this page is on screen, the app is in front and a relay is paired: read now, then the
            // heartbeat every 10 s (only what is new). The quant account's rows are built in.
            .task(id: [appActive, demo.isLive, demo.scope != .quant]) {
                guard appActive, demo.isLive, demo.scope != .quant else { return }
                await IBKRActivityStore.shared.runPolling()
            }
    }

    // MARK: Once paired

    @ViewBuilder private var liveContent: some View {
        let store = IBKRActivityStore.shared
        let entries = IBKRActivityList.timeline(store.items, filter: liveFilter, search: search)
        let others = demo.scope == .all ? builtInRows : []
        // 资金: the totals per type and currency over every cash record (not only the searched ones).
        if liveFilter == .cash, !searching, !IBKRActivityList.cash(store.items).isEmpty {
            DesktopCard {
                VStack(alignment: .leading, spacing: 18) {
                    DesktopSectionTitle(title: "资金合计", subtitle: "入金、出金、分红、利息、费用与税")
                    DesktopIBKRCashSummary(items: store.items)
                }
            }
            .transition(.opacity)
            .accessibilityIdentifier("activity_cash_summary")
        }
        if !entries.isEmpty || others.isEmpty {
            DesktopCard {
                VStack(alignment: .leading, spacing: 18) {
                    if demo.scope == .all {
                        DesktopSectionTitle(title: "个人账户", subtitle: "IBKR 成交、委托、资金与持仓变化")
                    }
                    if entries.isEmpty {
                        liveEmpty
                    } else {
                        DesktopIBKRTimeline(entries: entries, selection: $selectedEntry)
                    }
                }
            }
        }
        if !others.isEmpty {
            sampleCard(others, title: "量化账户")
                .transition(.opacity)
        }
    }

    /// Nothing to list: no search match, or nothing of the picked type yet.
    @ViewBuilder private var liveEmpty: some View {
        if searching {
            ContentUnavailableView.search(text: query)
        } else {
            ContentUnavailableView(emptyTitle, systemImage: "clock")
        }
    }

    private var emptyTitle: String {
        switch liveFilter {
        case .all: "还没有交易记录"
        case .trades: "还没有成交或委托"
        case .cash: "还没有资金流水"
        case .positions: "还没有持仓变化"
        }
    }

    // MARK: Before pairing

    /// The built-in rows (before pairing, 量化, or while the IBKR account has none; 全部 also lists the quant ones
    /// under `title` after the IBKR timeline).
    private func sampleCard(_ rows: [DemoActivity], title: String? = nil) -> some View {
        DesktopCard {
            VStack(spacing: 0) {
                if let title {
                    DesktopSectionTitle(title: title, subtitle: "策略成交、分红、内部划转与系统事件")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 6)
                }
                if rows.isEmpty {
                    if search.trimmingCharacters(in: .whitespaces).isEmpty {
                        ContentUnavailableView("暂无动态", systemImage: "clock", description: Text("当前范围暂无此类事件。"))
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                }
                ForEach(rows) { item in
                    Button { selected = item } label: {
                        HStack(spacing: 20) {
                            Image(systemName: item.icon).font(.system(size: 17)).foregroundStyle(DesktopTheme.blue)
                                .frame(width: 46, height: 46).background(DesktopTheme.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    Text(item.title).font(.system(size: 14, weight: .semibold))
                                    DesktopPill(text: item.owner.rawValue, color: item.owner == .quant ? DesktopTheme.orange : DesktopTheme.blue)
                                }
                                Text(item.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 8) {
                                if let amount = item.amount {
                                    Text(DesktopTheme.signedMoney(amount)).font(.system(size: 15, weight: .semibold, design: .rounded))
                                }
                                Text(item.time).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.tertiary)
                        }.padding(.vertical, 24).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if item.id != rows.last?.id { Divider().opacity(0.5) }
                }
            }
        }
    }
}
