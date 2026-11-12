import SwiftUI
import PortSightKit

/// 总览: the terminal's front page — the IBKR re-authorization banner when IBKR asks for it, money first, then
/// anything that needs a look, the Mac mini, strategies and the latest alerts.
struct DesktopTerminalOverview: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @EnvironmentObject private var terminal: TerminalDemo
    @EnvironmentObject private var market: MarketStatusViewModel
    @ObservedObject private var server = ServerStore.shared
    @Environment(\.desktopAppActive) private var appActive
    /// Passed on into the notice sheet, like `demo`, so its link button reaches ContentView.
    @Environment(\.openNoticeLink) private var openNoticeLink
    let open: (DesktopSection) -> Void
    /// Opens 交易 · 线路, scrolled to the given line (nil: top of the page).
    let openLine: (String?) -> Void

    @State private var hoveredValue: Double?
    @State private var range: AssetTrendRange = .all
    @State private var openNotice: DemoNotice?
    @State private var openAlert: TerminalAlert?
    @State private var openAsset: PortfolioAsset?

    /// Critical notices, unread critical alerts, unmounted or full disks (shared rules in PortSightKit).
    private var attentionItems: [AttentionItem] {
        AttentionItems.build(demo: demo, terminal: terminal, host: server.host)
    }

    var body: some View {
        DesktopFullPage(maxWidth: 1_400, spacing: 22) {
            // Nothing here unless IBKR needs re-authorizing (or just reported back): no empty row otherwise.
            DesktopIBKRBanner()

            header
                .accessibilityIdentifier("terminal_total")

            DesktopPageSection(title: "服务器", subtitle: serverSubtitle, spacing: 14) {
                serverSummary
            } trailing: {
                Button("服务器详情") { open(.server) }.buttonStyle(.link)
            }

            // The built-in lines, paired or not: the relay has no source for the lines' results (returns, fills,
            // checks) yet, so they look the same as before pairing.
            DesktopPageSection(title: "策略", subtitle: "模拟盘只看比例，不和真实资产相加", spacing: 14) {
                HStack(alignment: .top, spacing: 36) {
                    ForEach(DemoTerminalData.lines) { line in
                        Button { openLine(line.id) } label: { DesktopLineSummary(line: line) }
                            .buttonStyle(.plain)
                            .help("在 交易 · 线路 查看 " + line.title)
                            .accessibilityIdentifier("overview_line_" + line.id)
                    }
                }
            } trailing: {
                Button("全部线路") { openLine(nil) }.buttonStyle(.link)
            }

            DesktopPageSection(title: "最新告警", spacing: 8) {
                VStack(spacing: 0) {
                    ForEach(Array(terminal.alerts.prefix(3).enumerated()), id: \.element.id) { index, alert in
                        if index > 0 { Divider().opacity(0.5) }
                        // Same as the 需要处理 rows: click opens the detail, which marks it read.
                        Button { openAlert = alert } label: {
                            DesktopAlertRow(alert: alert, isRead: terminal.read.contains(alert.id))
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(DesktopHoverRowStyle())
                        .padding(.vertical, 4)
                    }
                }
            } trailing: {
                // Alerts live in the bell's notification panel.
                Button("全部告警") { demo.showNotifications = true }.buttonStyle(.link)
            }
        }
        // Every figure rolls (numericText) when the scope changes.
        .animation(.smooth, value: demo.scope)
        .animation(.smooth, value: server.fetchedAt)
        .animation(.smooth, value: IBKRStore.shared.bannerVisible)
        // /ibkr/status now, then every 6 s while the banner is up (IBKRStore.runBannerPolling). Restarted when the
        // banner appears, the app comes back to the front or the pairing changes; nothing is read in the background.
        // The page leaves the window when another section is picked, which cancels it.
        .task(id: BannerPolling(active: appActive, bannerVisible: IBKRStore.shared.bannerVisible,
                                pairing: server.pairingState)) {
            guard appActive else { return }
            await IBKRStore.shared.runBannerPolling()
        }
        // Once paired: the value curve (1月) every 10 s while the page is on screen and the app in front.
        .pollsIBKREquity(.standard, active: appActive)
        .closesForPush($openNotice)
        .sheet(item: $openNotice) { notice in
            DesktopSheetContainer(title: "通知详情", width: 520, height: 480, showsTitleBar: false) {
                DemoNoticeDetail(notice: notice)
            }
            .environmentObject(demo)
            .environment(\.openNoticeLink, openNoticeLink)
        }
        .closesForPush($openAlert)
        .sheet(item: $openAlert) { alert in
            DesktopSheetContainer(title: "告警详情", width: 520, height: 480, showsTitleBar: false) {
                DesktopAlertDetail(alert: alert)
            }
            .environmentObject(terminal)
        }
        .closesForPush($openAsset)
        .sheet(item: $openAsset) { asset in
            DesktopSheetContainer(title: asset.symbol + " · " + asset.name, width: 640, height: 560) {
                AssetDetailView(asset: asset)
            }
            .environmentObject(demo).environmentObject(market)
        }
        .onChange(of: demo.showNotifications) { _, show in
            if show { openNotice = nil; openAlert = nil; openAsset = nil }
        }
    }

    private func handle(_ item: AttentionItem) {
        switch item.target {
        case .notice(let notice): openNotice = notice
        case .alert(let alert): openAlert = alert
        case .server: open(.server)
        }
    }

    /// Total with 累计 and 今日 on the left, the asset curve, the key figures, then 需要处理 on the right — always
    /// one row. Narrowing the window first closes the gap before 需要处理's chevrons, then shortens the curve (300 → 80 pt).
    private var header: some View {
        OverviewHeaderLayout(spacing: 28, trendRange: 80...300, hasAttention: !attentionItems.isEmpty) {
            moneySummary
            trend
            keyFigures.fixedSize()
            attention
        }
    }

    @ViewBuilder private var attention: some View {
        if !attentionItems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("需要处理").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                ForEach(attentionItems) { item in
                    Button { handle(item) } label: {
                        DesktopAttentionRow(item: item).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(DesktopHoverRowStyle())
                }
            }
            .accessibilityIdentifier("terminal_attention")
        }
    }

    private var moneySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
                Text("总资产 · " + demo.scope.rawValue).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Text(DesktopTheme.money(hoveredValue ?? demo.total))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit().contentTransition(.numericText()).lineLimit(1)
                VStack(alignment: .leading, spacing: 3) {
                    pnlLine("累计", pnlText(demo.pnl, of: demo.principal), value: demo.pnl)
                    pnlLine("今日", pnlText(demo.dayPnL, of: demo.total - demo.dayPnL), value: demo.dayPnL)
                }
                .accessibilityIdentifier("terminal_pnl")
                // 「非实时 · 截至 …」 while the IBKR figures are not live.
                if let note = demo.liveNote {
                    Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("terminal_live_note")
                }
                Button { open(.remote) } label: { Label("远程桌面", systemImage: "rectangle.on.rectangle") }
                    .buttonStyle(.glass).controlSize(.large)
                    .padding(.top, 10)
            }
            .fixedSize()
    }

    /// The value history over the standard range (1月): the real IBKR curve once it has been read, else the
    /// built-in one (PortfolioCurve; before pairing the built-in curve as it always was).
    private var trend: some View {
        let curve = PortfolioCurve(scope: demo.scope)
        return AssetTrendChart(snapshots: curve.chartPoints().map { AssetChartSnapshot(date: $0.date, value: $0.value) },
                               principal: demo.principal, currentTotalAsset: demo.total,
                               selectedAssetValue: $hoveredValue, metric: .amount, showsRangePicker: false,
                               chartHeight: 112, rangeSelection: $range, showsAxes: false,
                               groupsByDay: !curve.isReal, dateStyle: curve.dateStyle, markers: curve.flows)
            .frame(height: 122)
            .accessibilityIdentifier("terminal_trend_chart")
    }

    /// 「+$1.00 · +0.10%」 (「—」 for the percentage when its base is 0).
    private func pnlText(_ value: Double, of base: Double) -> String {
        DesktopTheme.signedMoney(value) + " · " + DesktopTheme.percent(value, of: base)
    }

    /// A 累计 / 今日 line under the total, in profit / loss colour.
    private func pnlLine(_ label: String, _ text: String, value: Double) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(.secondary)
            Text(text).fontWeight(.semibold)
                .foregroundStyle(DesktopTheme.pnlColor(value)).monospacedDigit()
                .contentTransition(.numericText(value: value))
        }
        .font(.system(size: 13))
    }

    /// 持仓市值 · 现金, then today's best and worst holding, as a 2 × 2 grid.
    /// 累计 sits under the total and unread alerts on the bell, so neither repeats here.
    private var keyFigures: some View {
        let movers = demo.bestAndWorst
        return Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 18) {
            GridRow {
                DesktopStat(label: "持仓市值", value: DesktopTheme.money(demo.total - demo.cash),
                            detail: "\(demo.holdings.count) 项资产")
                DesktopStat(label: "现金", value: DesktopTheme.money(demo.cash), detail: "只计一次")
            }
            GridRow {
                if movers.isEmpty {
                    DesktopStat(label: "今日最佳", value: "—", detail: "今天没有变动")
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                } else {
                    ForEach(movers, id: \.holding.id) { mover in
                        Button { openAsset = mover.holding.asset } label: {
                            DesktopMoverStat(label: mover.label, holding: mover.holding)
                        }
                        .buttonStyle(DesktopHoverRowStyle(inset: 6))
                        .help(mover.holding.name)
                    }
                    if movers.count == 1 { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                }
            }
            .accessibilityIdentifier("terminal_movers")
        }
    }

    private var serverSubtitle: String {
        guard let host = server.host else {
            return server.pairingState == .unpaired ? "尚未接入" : (server.lastFailure != nil ? "暂时连不上" : "正在读取")
        }
        return (host.host?.hostname ?? "Mac mini") + " · " + (server.isSample ? "尚未配对" : ServerDates.clock(server.fetchedAt))
    }

    @ViewBuilder private var serverSummary: some View {
        if let host = server.host, host.hasData {
            let summary = host.summary
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        DesktopStatusDot(color: DesktopStatus.color(relay: summary?.state), size: 10)
                        Text(summary?.state == "ok" ? "运行正常" : "需要留意")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                    }
                    Text("心跳正常 \(summary?.heartbeats_ok ?? 0) · 异常 \(summary?.heartbeats_problem ?? 0) · 活跃告警 \(summary?.active_alerts ?? 0)")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                DesktopStat(label: "负载（5 分钟）", value: number(host.host?.load?.m5), detail: "\(host.host?.cpu_count ?? 0) 核")
                DesktopStat(label: "内存", value: pressure(host.host?.memory?.pressure),
                            detail: "空闲 " + number(host.host?.memory?.free_pct, suffix: "%"))
                let thermal = host.host?.thermal
                DesktopStat(label: "CPU / GPU 温度", value: DesktopStatus.temperatures(thermal),
                            detail: DesktopStatus.thermalProblem(thermal) ?? Self.power(host.host?.power))
            }
            HStack(alignment: .top, spacing: 28) {
                ForEach(StorageVolume.volumes(from: host)) { DesktopVolumeRow(volume: $0) }
            }
        } else if let host = server.host {
            ContentUnavailableView("暂无数据", systemImage: "macmini",
                                   description: Text(host.message ?? "Mac mini 上的主机状态任务还没写入数据。"))
        } else if server.pairingState != .unpaired {
            ContentUnavailableView(server.lastFailure != nil ? "暂时连不上" : "正在读取", systemImage: "macmini",
                                   description: Text("已配对，还没读到主机状态。"))
        } else {
            ContentUnavailableView("尚未接入", systemImage: "macmini", description: Text("Mac mini 到位并配对后显示实时状态。"))
        }
    }

    private static func power(_ power: HostPower?) -> String {
        switch power?.kind {
        case "ac": "市电"
        case "battery": power?.percent.map { "电池 \($0)%" } ?? "电池"
        case "ups": "UPS"
        default: "—"
        }
    }

    private func number(_ value: Double?, suffix: String = "") -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...1))) + suffix
    }

    private func pressure(_ value: String?) -> String {
        switch value {
        case "normal": "正常"
        case "warn", "warning": "偏高"
        case "critical": "紧张"
        default: "—"
        }
    }
}

/// What restarts 总览's IBKR status polling.
private struct BannerPolling: Equatable {
    var active: Bool
    var bannerVisible: Bool
    var pairing: RelayPairingState
}

/// One row: [fixed, curve, fixed, flexible]. The two fixed views get their natural width; the curve gets what is
/// left after the last view's minimum, clamped to `trendRange`; the last view gets the rest.
private struct OverviewHeaderLayout: Layout {
    var spacing: CGFloat
    var trendRange: ClosedRange<CGFloat>
    var hasAttention: Bool

    private func widths(_ width: CGFloat, _ subviews: Subviews) -> [CGFloat] {
        guard subviews.count == 4 else { return subviews.map { $0.sizeThatFits(.unspecified).width } }
        let money = subviews[0].sizeThatFits(.unspecified).width
        let figures = subviews[2].sizeThatFits(.unspecified).width
        let free = max(0, width - money - figures - spacing * 3)
        // 需要处理 can shrink to its own content (text + a small gap + chevron), never below that.
        let attentionContent = hasAttention ? subviews[3].sizeThatFits(.unspecified).width : 0
        let trend = min(trendRange.upperBound, max(trendRange.lowerBound, free - attentionContent))
        return [money, trend, figures, max(0, free - trend)]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 1_200
        let w = widths(width, subviews)
        let height = zip(subviews, w).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(bounds.width, subviews)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: nil))
            x += width + spacing
        }
    }
}
