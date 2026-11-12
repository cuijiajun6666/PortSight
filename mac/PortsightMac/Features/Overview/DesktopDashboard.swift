import SwiftUI
import PortSightKit

struct DesktopDashboard: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @EnvironmentObject private var market: MarketStatusViewModel
    /// The IBKR account card appears once a relay is paired (RelayNotices.usesRelay reads this store).
    @ObservedObject private var server = ServerStore.shared
    /// The value chart's range is read from the relay only while the window is in front.
    @Environment(\.desktopAppActive) private var appActive
    @State private var metric: PortfolioTrendMetric = .amount
    /// Before pairing: the built-in curve's range (picked beside 金额 / 收益率, as it always was).
    @State private var trendRange: AssetTrendRange = .all
    /// Once paired: the IBKR range under the chart (1天 … 全部), read from the relay while the dashboard is on screen.
    /// The chart opens on 全部 (the whole history).
    @State private var equityRange: IBKREquityRange = .all
    @State private var selectedValue: Double?
    @State private var selectedNews: RelatedMarketNews?
    /// 最近动态 once paired: the IBKR order (its status changes and fills) or record a row stands for.
    @State private var selectedActivity: DesktopIBKRSelection?
    let openPage: (DesktopPage) -> Void
    let openSheet: (DesktopSheet) -> Void
    let openAsset: (PortfolioAsset) -> Void

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width >= DesktopCardGrid.wideBreakpoint
            let sideWidth = DesktopCardGrid.width(span: 4, columns: 12, available: geometry.size.width)
            DesktopPageScrollView {
                VStack(spacing: DesktopCardGrid.spacing) {
                    if demo.showNotifications {
                        hero
                        let cardCount: CGFloat = demo.scope == .personal ? 2 : 3
                        let cardWidth = max(0, (geometry.size.width - DesktopCardGrid.spacing * (cardCount - 1)) / cardCount)
                        HStack(alignment: .top, spacing: DesktopCardGrid.spacing) {
                            DesktopPortfolioSummaryCard { openPage(.analysis) }
                                .frame(width: cardWidth)
                            if demo.scope != .personal {
                                DesktopQuantSummaryCard { openPage(.strategies) }
                                    .frame(width: cardWidth)
                            }
                            DesktopRelatedNewsCard(scope: demo.scope, openArticle: { selectedNews = $0 })
                                .frame(width: cardWidth)
                        }
                        let activityWidth = max(0, (geometry.size.width - DesktopCardGrid.spacing * 2) / 3)
                        HStack(alignment: .top, spacing: DesktopCardGrid.spacing) {
                            VStack(spacing: DesktopCardGrid.spacing) {
                                activityCard
                                DesktopUpcomingEventCard(scope: demo.scope)
                            }
                            .frame(width: activityWidth)
                            DesktopSectorFlowCard()
                                .frame(width: activityWidth * 2 + DesktopCardGrid.spacing)
                        }
                    } else if isWide {
                        HStack(alignment: .top, spacing: DesktopCardGrid.spacing) {
                            VStack(spacing: DesktopCardGrid.spacing) {
                                hero
                                HStack(alignment: .top, spacing: DesktopCardGrid.spacing) {
                                    DesktopPortfolioSummaryCard { openPage(.analysis) }
                                        .frame(maxWidth: .infinity)
                                    if demo.scope != .personal {
                                        DesktopQuantSummaryCard { openPage(.strategies) }
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                            .frame(minWidth: 640, maxWidth: .infinity)
                            VStack(spacing: DesktopCardGrid.spacing) {
                                DesktopRelatedNewsCard(scope: demo.scope, openArticle: { selectedNews = $0 })
                                activityCard
                                DesktopUpcomingEventCard(scope: demo.scope)
                            }
                            .frame(width: sideWidth)
                        }
                    } else {
                        hero
                        DesktopPortfolioSummaryCard { openPage(.analysis) }
                        if demo.scope != .personal {
                            DesktopQuantSummaryCard { openPage(.strategies) }
                        }
                        DesktopRelatedNewsCard(scope: demo.scope, openArticle: { selectedNews = $0 })
                        activityCard
                        DesktopUpcomingEventCard(scope: demo.scope)
                    }
                    // The personal IBKR account, read through the Mac mini: only once paired (before that the page
                    // is the built-in sample, unchanged), and not on the 量化 scope, which holds no personal money.
                    if RelayNotices.usesRelay && demo.scope != .quant {
                        DesktopIBKRAccountCard()
                    }
                    if !demo.showNotifications {
                        DesktopSectorFlowCard()
                    }
                    HStack {
                        Label("USD", systemImage: "circle.dotted").font(.system(size: 10))
                        Spacer()
                        Text("PORTSIGHT / DESKTOP").font(.system(size: 9, weight: .medium)).tracking(2)
                    }.foregroundStyle(.tertiary).padding(.horizontal, 3).padding(.top, 4)
                }
            }.scrollIndicators(.hidden)
        }
        // Every figure rolls (numericText) when the scope changes.
        .animation(.smooth, value: demo.scope)
        .onChange(of: demo.scope) { _, _ in selectedValue = nil }
        .closesForPush($selectedNews)
        .sheet(item: $selectedNews) { article in
            DesktopSheetContainer(title: "相关新闻", width: 560, height: 380) {
                DesktopNewsDetail(article: article)
            }
        }
    }

    private var hero: some View {
        let feed = chartFeed
        return VStack(alignment: .leading, spacing: 10) {
            DesktopAssetTrendRow {
                assetSummary(feed)

                // Both columns start at the asset amount's top edge.
                // The controls belong to the summary column below market status.
                Color.clear
                    .overlay { chartColumn(feed) }
                    .padding(.top, 8)
                    .padding(.bottom)
            }
            .frame(height: DesktopCardGrid.rowHeight + 38, alignment: .top)

            Divider()
            DesktopAllocationSummary(openPositions: { openPage(.positions) }, openAsset: openAsset)
        }
        .padding(.leading, 27)
        .padding(.trailing, 16)
        .padding(.top)
        .padding(.top, 5)
        .padding(.bottom, 16)
        .background(DesktopTheme.card, in: DesktopTheme.surfaceShape)
        .overlay { DesktopTheme.surfaceShape.strokeBorder(DesktopTheme.border) }
        .modifier(DesktopCardShadow())
        // Once paired: the picked range now, then every 10 s (a 304 when nothing changed), while the dashboard is on
        // screen and the window in front; restarted when the range changes.
        .pollsIBKREquity(equityRange, active: appActive)
    }

    /// The curve, then (once paired) the range picker and how the relay worked the figures out.
    private func chartColumn(_ feed: DashboardChartFeed) -> some View {
        VStack(spacing: 8) {
            GeometryReader { chartArea in
                AssetTrendChart(snapshots: feed.snapshots, principal: feed.principal,
                                currentTotalAsset: feed.currentTotal, selectedAssetValue: $selectedValue,
                                metric: metric, showsRangePicker: false,
                                chartHeight: max(80, chartArea.size.height),
                                rangeSelection: feed.curve == nil ? $trendRange : nil,
                                groupsByDay: feed.groupsByDay, dateStyle: feed.dateStyle, markers: feed.markers)
                    .accessibilityIdentifier("asset_trend_chart")
            }
            if let curve = feed.curve {
                DesktopCapsulePicker(title: "资产走势区间", options: IBKREquityRange.allCases,
                                     selection: $equityRange, label: \.title)
                    .accessibilityIdentifier("portfolio_equity_range")
                if !curve.warnings.isEmpty {
                    Text(curve.warnings.joined(separator: " · "))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).lineLimit(2)
                        .frame(maxWidth: .infinity)
                        .help(curve.warnings.joined(separator: "\n"))
                        .accessibilityIdentifier("portfolio_equity_warnings")
                }
            }
        }
    }

    /// What the chart draws. Before pairing: the built-in curve with its own range picker, exactly as it always was.
    /// Once paired: the picked IBKR range — the real curve when it has been read (收益率 is IBKR's time-weighted return),
    /// else the built-in one — with deposits and withdrawals marked.
    private var chartFeed: DashboardChartFeed {
        guard demo.isLive else {
            return DashboardChartFeed(snapshots: demo.snapshots, principal: demo.principal, currentTotal: demo.total)
        }
        let curve = PortfolioCurve(scope: demo.scope, range: equityRange)
        let points = curve.chartPoints()
        var feed = DashboardChartFeed(snapshots: [], principal: 1, currentTotal: 1, markers: curve.flows,
                                      dateStyle: curve.dateStyle, groupsByDay: !curve.isReal, curve: curve)
        if metric == .returnRate {
            // Growth since the range's start (1 = start), so the chart's 收益率 is the return over the range.
            feed.snapshots = points.map { AssetChartSnapshot(date: $0.date, value: $0.growth) }
            feed.currentTotal = points.last?.growth ?? 1
        } else {
            let first = points.first?.value ?? 0, last = points.last?.value ?? 0
            feed.snapshots = points.map { AssetChartSnapshot(date: $0.date, value: $0.value) }
            // The line is green or red by the range's P&L (deposits and withdrawals left out on the real curve).
            feed.currentTotal = last
            feed.principal = last - (curve.rangePnL ?? last - first)
        }
        return feed
    }

    /// The big figure: the total (or the hovered value), or its return — on principal for the built-in curve before
    /// pairing, over the range once paired.
    private func heroValue(_ feed: DashboardChartFeed) -> String {
        guard metric == .returnRate else { return DesktopTheme.money(selectedValue ?? demo.total) }
        return DesktopTheme.percent((selectedValue ?? feed.currentTotal) - feed.principal, of: feed.principal)
    }

    private func assetSummary(_ feed: DashboardChartFeed) -> some View {
        VStack(alignment: .leading, spacing: 0) {

            Text(heroValue(feed))
                .font(.system(size: 38, weight: .semibold, design: .rounded)).tracking(-0.8)
                .monospacedDigit().contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.65)
                .accessibilityIdentifier("portfolio_value")
            // On the real curve: the picked range's P&L and time-weighted return; otherwise since the start.
            if let curve = feed.curve, curve.isReal, let pnl = curve.rangePnL {
                pnlRow(pnl, fraction: curve.rangeReturn, label: curve.range.title + "累计")
                    .padding(.top, 10)
                    .accessibilityIdentifier("portfolio_range_pnl")
            } else {
                pnlRow(demo.pnl, fraction: Self.fraction(demo.pnl, of: demo.principal), label: "累计")
                    .padding(.top, 10)
            }
            pnlRow(demo.dayPnL, fraction: Self.fraction(demo.dayPnL, of: demo.total - demo.dayPnL), label: "当日盈亏")
                .padding(.top, 7)
                .accessibilityIdentifier("portfolio_day_pnl")
            // 「非实时 · 截至 …」 while the IBKR figures are not live.
            if let note = demo.liveNote {
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .accessibilityIdentifier("portfolio_live_note")
            }
            HStack(spacing: 8) {
                Circle().fill(market.session == .regular ? DesktopTheme.green : .secondary.opacity(0.55))
                    .frame(width: 5, height: 5)
                Text("美股" + market.displayStatus).font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
            .padding(.top, 12)
            HStack(spacing: 12) {
                DesktopCapsulePicker(title: "资产指标", options: PortfolioTrendMetric.allCases,
                                     selection: $metric, label: { $0.rawValue })
                    .accessibilityIdentifier("portfolio_metric")
                // Once paired the range is picked under the chart.
                if feed.curve == nil {
                    DesktopCapsulePicker(title: "资产趋势范围", options: AssetTrendRange.allCases,
                                         selection: $trendRange, label: { $0.rawValue })
                        .accessibilityIdentifier("portfolio_range")
                }
            }
            .padding(.top, 12)
        }
    }

    /// `part / whole`, nil when `whole` is 0 (never a division by zero).
    private static func fraction(_ part: Double, of whole: Double) -> Double? {
        whole != 0 && part.isFinite && whole.isFinite ? part / whole : nil
    }

    /// 「↗ +$1.00 (+0.10%) 累计」 in profit / loss colour; the percentage is 「—」 without a base.
    private func pnlRow(_ value: Double, fraction: Double?, label: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: value >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .semibold))
            Text(DesktopTheme.signedMoney(value)).fontWeight(.semibold)
                .contentTransition(.numericText(value: value))
            Text("(" + (fraction.map { DesktopTheme.percent($0) } ?? "—") + ")")
                .contentTransition(.numericText(value: fraction ?? 0))
            Text(label).foregroundStyle(.secondary).padding(.leading, 3)
        }
        .monospacedDigit()
        .font(.system(size: 12))
        .foregroundStyle(DesktopTheme.pnlColor(value))
    }

    private var activityCard: some View {
        DesktopCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    DesktopSectionTitle(title: "最近动态")
                    Spacer()
                    Button { openSheet(.report) } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.small)
                    .foregroundStyle(.primary).help("查看收益复盘")
                    .accessibilityLabel("查看收益复盘")
                    Button { openPage(.activity) } label: { Image(systemName: "arrow.up.right") }.buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.small).foregroundStyle(.primary).help("查看全部动态")
                }
                // Read once: once paired every read goes through the whole activity store.
                let rows = demo.activities
                if rows.isEmpty {
                    Text("暂无动态").font(.system(size: 11)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("dashboard_activity_empty")
                }
                ForEach(Array(rows.prefix(3))) { item in
                    // Once paired the real IBKR rows (IBKRTimelineEntry.asDemoActivity) open their order or record;
                    // the built-in rows shown with them have no detail.
                    if demo.isLive, let selection = DesktopIBKRSelection(activityID: item.id) {
                        Button { selectedActivity = selection } label: {
                            activityRow(item).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help("查看详情")
                    } else {
                        activityRow(item)
                    }
                }
            }
        }
        .closesForPush($selectedActivity)
        .sheet(item: $selectedActivity) { selection in
            DesktopSheetContainer(title: selection.title) { DesktopIBKREntryDetail(entry: selection.entry) }
        }
    }

    private func activityRow(_ item: DemoActivity) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.icon).font(.system(size: 12)).foregroundStyle(DesktopTheme.blue)
                .frame(width: 30, height: 30).background(DesktopTheme.blue.opacity(0.07), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 12, weight: .medium))
                Text(item.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                Text(item.time).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }


}

/// What the dashboard's value chart draws (DesktopDashboard.chartFeed).
private struct DashboardChartFeed {
    var snapshots: [AssetChartSnapshot]
    /// The chart's base for 收益率 and for its colour.
    var principal: Double
    var currentTotal: Double
    var markers: [AssetTrendMarker] = []
    var dateStyle: AssetTrendDateStyle = .builtIn
    var groupsByDay = true
    /// Once paired: the curve of the picked range (nil before pairing).
    var curve: PortfolioCurve?
}

#Preview("Dashboard") {
    DesktopDashboard(openPage: { _ in }, openSheet: { _ in }, openAsset: { _ in })
        .environmentObject(PortfolioDemo())
        .environmentObject(MarketStatusViewModel())
        .buttonStyle(.glass)
        .modifier(DesktopContentSurface())
        .background(.ultraThinMaterial)
        .frame(width: 1420, height: 900)
}

