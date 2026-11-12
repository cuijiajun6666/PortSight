//
//  TerminalOverviewView.swift
//  PortSight
//
//  总览 tab: money, what needs attention now, one line per strategy and one for the Mac mini. When IBKR asks for its
//  weekly re-authorization, a banner with 重新授权 sits above everything (IBKRBannerSection). Once paired, the hero's
//  figures (the personal IBKR account and its value over the last month) are read again every 10 s while this tab is
//  selected and the app in front.
//  Same backdrop as the 资产 page (terminalPageList).
//

import SwiftUI
import SwiftData
import Charts
import PortSightKit

struct TerminalOverviewView: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @EnvironmentObject private var terminal: TerminalDemo
    @ObservedObject private var server = ServerStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selectedTab: Int

    /// What restarts the IBKR status polling: the app coming to the front, the banner going up or down, the pairing.
    private struct BannerPolling: Equatable {
        let active: Bool
        let bannerVisible: Bool
        let pairing: RelayPairingState
    }

    /// What restarts the account reading: 总览 being the selected tab with the app in front, and the pairing.
    private struct AccountPolling: Equatable {
        let inFront: Bool
        let paired: Bool
        let pairing: RelayPairingState
    }

    /// ContentView's tag for this tab.
    private static let tab = 10
    /// Everything on 总览 (the IBKR account behind the hero, alerts, notices, the IBKR login state, new fills) is read
    /// again this often while 总览 is the tab on screen and the app is in front; never on another tab or in the
    /// background.
    private static let accountInterval: TimeInterval = 10

    var body: some View {
        let polling = BannerPolling(active: scenePhase == .active, bannerVisible: IBKRStore.shared.bannerVisible,
                                    pairing: server.pairingState)
        // Not under the 消息中心 or 设置 sheet either, like the 资产 page's polling.
        let accountPolling = AccountPolling(inFront: selectedTab == Self.tab && scenePhase == .active
                                                && !demo.showNotifications && !demo.showSettings,
                                            paired: RelayNotices.usesRelay, pairing: server.pairingState)
        NavigationStack {
            PortSightList {
                // IBKR re-authorization first of all: nothing else on the page matters while it is due.
                IBKRBannerSection()

                // Total, change, then holdings / cash beside today's biggest movers, right under the toolbar.
                Section {
                    VStack(spacing: 16) {
                        // Clear of the row's rounded corner, which clips whatever sits in it.
                        hero.padding(.top, overviewNumberTop)
                        HStack(alignment: .top) {
                            moneyCard
                            moversCard
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                // Only when something needs a look: critical notices, problem alerts, full or missing disks.
                if !actionItems.isEmpty {
                    Section {
                        ForEach(actionItems) { item in
                            Button { open(item) } label: { actionRow(item) }
                                .foregroundStyle(.primary)
                        }
                    } header: {
                        Text("需要处理")
                    }
                }

                Section {
                    // The quant lines are not on the relay yet: their built-in figures, paired or not (as on 交易).
                    ForEach(DemoTerminalData.lines) { line in
                        NavigationLink { TerminalLineDetailView(line: line) } label: { lineRow(line) }
                    }
                } header: {
                    Text("策略")
                }

                Section {
                    Button { selectedTab = 4 } label: { serverRow }
                        .foregroundStyle(.primary)
                } header: {
                    Text("服务器")
                }
            }
            // No title: the content starts right under the toolbar, on the 资产 page's backdrop.
            .terminalPageList()
            // Every figure rolls (numericText) when the scope changes.
            .animation(.smooth, value: demo.scope)
            .animation(.smooth, value: server.fetchedAt)
            .toolbar { DemoToolbar() }
            .navigationDestination(isPresented: Binding(get: { openNotice != nil }, set: { if !$0 { openNotice = nil } })) {
                if let openNotice { DemoNoticeDetail(notice: openNotice) }
            }
            .navigationDestination(item: $openAlert) { TerminalAlertDetailView(alert: $0) }
            // The status now, then every 6 s while the banner is up (never faster); nothing in the background.
            .task(id: polling) {
                guard polling.active else { return }
                await IBKRStore.shared.runBannerPolling()
            }
            .animation(.smooth, value: IBKRStore.shared.banner()?.state)
        }
        // A notice's link (e.g. 去重新授权) shows this tab: back to the top, where the banner is. On the stack, which
        // stays in place while a pushed page covers the list.
        .onChange(of: NoticeLinkRoute.shared.opened) {
            openNotice = nil
            openAlert = nil
        }
        // Once paired, while this tab is selected and the app in front: everything every 10 s (on the stack, so a
        // pushed page does not stop it). Nothing before pairing, in the background, under a sheet or on another tab.
        .task(id: accountPolling) {
            guard accountPolling.inFront, accountPolling.paired else { return }
            await Self.pollAccount()
        }
    }

    /// The relay now (ServerStore.refresh: /host, alerts, notices, the IBKR login state and account, new activity),
    /// and the account's value over the last month (the hero's trend line; a 304 when nothing changed), then every
    /// 10 s until the task is cancelled. The read the app makes on coming to the front is shared, not doubled:
    /// ServerStore keeps automatic refreshes 10 s apart and the IBKR stores skip a read made moments ago.
    private static func pollAccount() async {
        while !Task.isCancelled {
            await ServerStore.shared.refresh()
            await IBKRStore.shared.refreshAccount()
            await IBKREquityStore.shared.load(.standard)
            try? await Task.sleep(for: .seconds(accountInterval))
        }
    }

    /// Space above the total, just enough to keep the "$" clear of the row's rounded corner.
    private let overviewNumberTop: CGFloat = 6

    /// The total with a bare trend line beside it, then 累计 and 今日 in profit / loss colours.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Text(terminalMoney(demo.total))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit().contentTransition(.numericText()).minimumScaleFactor(0.6).lineLimit(1)
                    .layoutPriority(1)
                // The last month: the personal account's real curve once read (the quant account's built-in value
                // added for 全部), the built-in curve otherwise.
                TerminalSparkline(values: sparkline.map(\.equity), up: sparklineUp(sparkline))
                    .frame(maxWidth: 120)
                    .frame(height: 40)
            }
            PnLSummary()
            // Once paired, while the IBKR figures are real but not live: 「非实时 · 截至 …」.
            if let note = demo.liveNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The hero's trend line (Portfolio.points: the real 1-month curve once read).
    private var sparkline: [DemoPoint] { demo.points(demo.scope) }

    /// Green when the real curve ends at or above where it started; the built-in one by the total against the
    /// principal, as before.
    private func sparklineUp(_ points: [DemoPoint]) -> Bool {
        guard Portfolio.hasRealHistory(demo.scope), let first = points.first, let last = points.last else {
            return demo.total >= demo.principal
        }
        return last.equity >= first.equity
    }

    // MARK: Cards

    private var moneyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            figure("持仓市值", terminalMoney(demo.total - demo.cash), icon: "chart.pie.fill")
            Divider()
            figure("现金", terminalMoney(demo.cash), icon: "dollarsign.circle.fill")
        }
        .modifier(OverviewCard())
    }

    private func figure(_ title: String, _ value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
                .minimumScaleFactor(0.7).lineLimit(1)
                .contentTransition(.numericText())
        }
    }

    /// Today's best and worst holding by percentage move (shared rule in PortSightKit).
    private var bestAndWorst: [(label: String, holding: DemoHolding)] { demo.bestAndWorst }

    private var moversCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(bestAndWorst.enumerated()), id: \.element.holding.id) { index, item in
                if index > 0 { Divider() }
                let change = item.holding.dayChange
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.label).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        HoldingIcon(symbol: item.holding.symbol, crypto: item.holding.kind == "加密货币")
                        Text(item.holding.symbol).font(.headline).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(TerminalFormat.percent(change)).font(.subheadline.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(TerminalStyle.pnl(change))
                            .contentTransition(.numericText(value: change))
                    }
                }
            }
            if bestAndWorst.isEmpty {
                Text("今天没有变动").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .modifier(OverviewCard())
    }

    // MARK: 需要处理

    /// Critical notices, unread critical alerts, unmounted or full disks (shared rules in PortSightKit).
    private var actionItems: [AttentionItem] {
        AttentionItems.build(demo: demo, terminal: terminal, host: server.host)
    }

    @State private var openNotice: DemoNotice?
    @State private var openAlert: TerminalAlert?

    private func open(_ item: AttentionItem) {
        switch item.target {
        case .notice(let notice): openNotice = notice
        case .alert(let alert): openAlert = alert
        case .server: selectedTab = 4
        }
    }

    private func actionRow(_ item: AttentionItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon).foregroundStyle(item.tone == .critical ? Color.red : .orange)
                .font(.title3).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
    }

    // MARK: Strategies and server, one line each

    private func lineRow(_ line: TradingLine) -> some View {
        let today = line.daily.returnPct
        return HStack(spacing: 10) {
            Image(systemName: line.icon).foregroundStyle(.secondary).frame(width: 22)
            Circle().fill(TerminalStyle.color(line.state)).frame(width: 7, height: 7)
            Text(line.title).font(.subheadline.weight(.semibold))
            TerminalModeBadge(mode: line.mode)
            Spacer()
            if TerminalLineSeal.isSealed(line) {
                Text("封存中").font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityHint(TerminalLineSeal.note)
            } else {
                Text(TerminalFormat.percent(today)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(TerminalStyle.pnl(today))
            }
        }
    }

    @ViewBuilder private var serverRow: some View {
        if let host = server.host, !host.hasData {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("暂无数据").font(.subheadline.weight(.semibold))
                    Text(host.message ?? "主机状态任务还没写入数据").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        } else if let host = server.host {
            let summary = host.summary
            // The host may report "ok" while a reading is 85 °C or more: the row still asks for attention then.
            let thermal = host.host?.thermal
            let hot = thermal?.overheated == true || (thermal?.hottest ?? .normal) >= .warm
            let state = summary?.state == "ok" && hot ? "warning" : summary?.state
            let ok = state == "ok"
            HStack(spacing: 10) {
                Circle().fill(TerminalStyle.color(relay: state)).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ok ? "运行正常" : "需要留意").font(.subheadline.weight(.semibold))
                    Text(serverProblem(host) ?? (host.host?.hostname ?? "Mac mini"))
                        .font(.caption).foregroundStyle(ok ? Color.secondary : .orange).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        } else {
            HStack {
                Text("Mac mini")
                Spacer()
                TerminalPendingBadge()
            }
        }
    }

    /// The one thing wrong with the Mac mini right now, if any.
    private func serverProblem(_ host: HostStatus) -> String? {
        let summary = host.summary
        var parts: [String] = []
        if let bad = summary?.heartbeats_problem, bad > 0 {
            parts.append("心跳 \(summary?.heartbeats_ok ?? 0)/\((summary?.heartbeats_ok ?? 0) + bad)")
        }
        if let alerts = summary?.active_alerts, alerts > 0 { parts.append("\(alerts) 条告警") }
        if let thermal = host.host?.thermal {
            if thermal.overheated { parts.append("过热降频") }
            parts += thermal.warmReadings.map { "\($0.name) \(HostThermal.text($0.celsius)) \($0.level.word)" }
        }
        if let pressure = host.host?.memory?.pressure, pressure != "normal" { parts.append("内存压力高") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A holding's real icon (SymbolLogoStore: logo.dev, downloaded once and kept), or the letter placeholder while it
/// loads or when there is none.
struct HoldingIcon: View {
    let symbol: String
    var crypto = false

    var body: some View {
        SymbolLogoView(symbol: symbol, crypto: crypto || SymbolLogoStore.isCrypto(symbol), size: 20)
    }
}

private struct OverviewCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
            .portSightCard(cornerRadius: 22)
    }
}

/// Just the line (and its soft fill) of the 资产 page's trend chart: no axes, labels or interaction.
struct TerminalSparkline: View {
    let values: [Double]
    let up: Bool

    var body: some View {
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let color: Color = up ? .green : .red
        Chart(Array(values.enumerated()), id: \.offset) { point in
            LineMark(x: .value("i", point.offset), y: .value("v", point.element))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            AreaMark(x: .value("i", point.offset), yStart: .value("min", low), yEnd: .value("v", point.element))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: low...max(high, low + 1))
        .chartXScale(domain: 0...max(values.count - 1, 1))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
