import SwiftUI
import Charts
import PortSightKit

func demoMoney(_ value: Double) -> String { value.formatted(.currency(code: "USD")) }
func demoPercent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(2))) }

struct DemoCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) { Image(systemName: icon).foregroundStyle(.secondary); Text(title).font(.headline); Spacer() }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .portSightCard(cornerRadius: 30)
    }
}
struct DemoHomeAdditions: View {
    @EnvironmentObject private var demo: PortfolioDemo
    var body: some View {
        VStack(spacing: 14) {
            HStack { Text("Portfolio Overview").font(.title3.bold()) }
            let pending = demo.pendingCritical
            if let first = pending.first {
                Button { demo.showNotifications = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(first.severity == "critical" ? .red : .orange)
                        VStack(alignment: .leading, spacing: 3) {
                            // The notice's own title (a relay notice says what it is about); several: how many.
                            Text(pending.count == 1 ? first.title + "待确认" : "\(pending.count) 条通知待确认")
                                .font(.subheadline.weight(.semibold))
                            Text("点击查看详情").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "chevron.right").font(.caption)
                    }.padding(14).background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if demo.isLive {
                    // Once paired the real day can be a loss: signed, in profit / loss colour.
                    metric("今日盈亏", value: signedMoney(demo.dayPnL), note: "不含入金与内部划转",
                           tint: demo.dayPnL >= 0 ? .green : .red)
                } else {
                    metric("今日盈亏", value: "+" + demoMoney(demo.dayPnL), note: "不含入金与内部划转", positive: true)
                }
                metric("可用现金", value: demoMoney(demo.cash),
                       note: "占总资产 " + (demo.total > 0 ? demoPercent(demo.cash / demo.total) : missingFigure))
            }
            if demo.scope == .all {
                DemoCard(title: "资金由谁管理", icon: "square.split.2x2") {
                    managerRow(.personal, color: .blue)
                    managerRow(.quant, color: .orange)
                    Text("同一只股票可以同时由你和量化系统持有，全部视角合并展示。").font(.caption).foregroundStyle(.secondary)
                }
            }
            // Once paired every card stays: the real figures, curve and records where the relay has them, the
            // built-in ones (the quant account, the review, the model status) everywhere else.
            DemoCard(title: "风险概览", icon: "shield.lefthalf.filled") {
                let dd = demo.points(demo.scope).map(\.drawdown).max() ?? 0
                HStack { Text("近 30 日最大回撤"); Spacer(); Text(demoPercent(dd)).monospacedDigit() }
                if demo.scope != .personal {
                    ProgressView(value: min(dd, 0.08), total: 0.08).tint(.orange)
                    HStack { Text("风险上限 8%"); Spacer(); Text("剩余 " + demoPercent(max(0, 0.08 - dd))) }.font(.caption).foregroundStyle(.secondary)
                }
                let nvda = demo.holdings.first { $0.symbol == "NVDA" }
                HStack { Text("NVDA 持仓占比"); Spacer(); Text(demoPercent(demo.total > 0 ? (nvda?.value ?? 0) / demo.total : 0)) }
                if demo.scope == .all, let exposure = nvdaExposure {
                    Text(exposure).font(.caption).foregroundStyle(.secondary)
                }
            }
            if demo.scope != .personal {
                NavigationLink { DemoStrategyDetail() } label: {
                    DemoCard(title: "量化系统", icon: "waveform.path.ecg") {
                        HStack { Label("保护检查中", systemImage: "pause.circle").foregroundStyle(.orange); Spacer(); Image(systemName: "chevron.right") }
                        LabeledContent("最近运行", value: "今天 10:32 · 已完成")
                        LabeledContent("下次计划调仓", value: "下一个交易日 09:35 ET")
                        HStack { Text("冠军模型"); Spacer(); Text("Alpha v3").foregroundStyle(.secondary) }
                        Text("1 个挑战者正在影子运行 · 点击查看策略与模型状态").font(.caption).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
            }
            NavigationLink { DemoReportDetail() } label: {
                DemoCard(title: "每日复盘", icon: "chart.xyaxis.line") {
                    Text(reviewLine).font(.subheadline)
                    HStack { Text("查看收益、基准、回撤与成本").font(.caption).foregroundStyle(.secondary); Spacer(); Image(systemName: "arrow.up.right") }
                }
            }.buttonStyle(.plain)
            DemoCard(title: "最近动态", icon: "clock.arrow.circlepath") {
                // Once paired: the personal IBKR account's records first, then the built-in quant ones.
                ForEach(Array(demo.activities.prefix(3))) { item in DemoActivityRow(item: item) }
                Text("入金和内部划转不计入投资收益。").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.top, 24)
    }

    /// 「个人 20 股 + 量化 30 股 = 50 股」: NVDA held by both accounts (real shares for 个人 once paired).
    private var nvdaExposure: String? {
        let lots = demo.lots(.all).filter { $0.symbol == "NVDA" }
        let personal = lots.filter { $0.owner == .personal }.reduce(0) { $0 + $1.quantity }
        let quant = lots.filter { $0.owner == .quant }.reduce(0) { $0 + $1.quantity }
        guard personal != 0 || quant != 0 else { return nil }
        func shares(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...4))) }
        return "个人 \(shares(personal)) 股 + 量化 \(shares(quant)) 股 = \(shares(personal + quant)) 股"
    }

    /// The 每日复盘 card's line: the built-in sentence before pairing; once paired from today's figures (which way
    /// the portfolio moved and the holding that moved it most).
    private var reviewLine: String {
        guard demo.isLive else { return "今日组合上涨，主要贡献来自 NVDA；现金比例保持稳定。" }
        let direction = demo.dayPnL >= 0 ? "上涨" : "下跌"
        guard let mover = demo.holdings.max(by: { abs($0.dayPnL) < abs($1.dayPnL) }), mover.dayPnL != 0 else {
            return "今日组合" + direction + "；现金比例保持稳定。"
        }
        return "今日组合" + direction + "，主要" + (mover.dayPnL >= 0 ? "贡献" : "拖累") + "来自 " + mover.symbol + "；现金比例保持稳定。"
    }
    private func signedMoney(_ value: Double) -> String { (value >= 0 ? "+" : "−") + demoMoney(abs(value)) }
    private func metric(_ title: String, value: String, note: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(tint).contentTransition(.numericText())
            Text(note).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).portSightCard(cornerRadius: 30)
    }
    private func metric(_ title: String, value: String, note: String, positive: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(positive ? .green : .primary).contentTransition(.numericText())
            Text(note).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).portSightCard(cornerRadius: 30)
    }
    private func managerRow(_ scope: PortfolioScope, color: Color) -> some View {
        Button { withAnimation(.easeInOut) { demo.scope = scope } } label: {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(scope.rawValue)
                Spacer()
                Text(demoMoney(demo.total(scope))).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
            }
        }.buttonStyle(.plain)
    }
}

struct DemoActivityRow: View {
    let item: DemoActivity
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.icon).frame(width: 32, height: 32).background(.primary.opacity(0.05), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.medium))
                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                Text(item.time + " · " + (item.owner == .all ? "内部划转" : item.owner.rawValue)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 5)
            if let amount = item.amount { Text(demoMoney(amount)).font(.subheadline).monospacedDigit() }
        }.padding(.vertical, 4)
    }
}
struct DemoActivityView: View {
    @EnvironmentObject private var demo: PortfolioDemo
    /// The built-in rows' categories (before pairing, the quant scope, and 个人 / 全部 until IBKR has records).
    @State private var filter = "全部"
    /// The IBKR record kinds (全部 / 交易 / 资金 / 持仓), once the real timeline is listed.
    @State private var liveFilter: IBKRActivityFilter = .all
    @State private var search = ""
    private static let builtInFilters = ["全部", "成交", "资金", "分红", "系统"]

    /// The personal IBKR account's own timeline is listed: paired, a scope with the personal account, and IBKR has
    /// records. Otherwise every row is a built-in one (demo.activities), as before pairing.
    private var listsIBKR: Bool {
        demo.isLive && demo.scope != .quant && !IBKRActivityStore.shared.items.isEmpty
    }

    /// The built-in rows when nothing real is listed: the type picker's category and the search.
    private var rows: [DemoActivity] { demo.activities.filter {
        (filter == "全部" || $0.category == filter) && matchesSearch($0)
    } }

    /// With the IBKR timeline under 全部: the built-in quant (and internal transfer) rows that follow it, for the
    /// IBKR picker's kind and the search. None under 个人, which lists the real account only.
    private var quantRows: [DemoActivity] {
        guard demo.scope == .all else { return [] }
        return demo.activities.filter { $0.owner != .personal && Self.includes(liveFilter, $0.category) && matchesSearch($0) }
    }

    private func matchesSearch(_ item: DemoActivity) -> Bool {
        search.isEmpty || (item.title + item.detail).localizedCaseInsensitiveContains(search)
    }

    /// A built-in row's category under the IBKR kinds: 交易 = 成交, 资金 = 资金 and 分红, 持仓 = none.
    private static func includes(_ filter: IBKRActivityFilter, _ category: String) -> Bool {
        switch filter {
        case .all: true
        case .trades: category == "成交" || category == "委托"
        case .cash: category == "资金" || category == "分红"
        case .positions: category == "持仓"
        }
    }

    /// Changes whenever the rows on screen change, so they move in and out with an animation (search, type, scope,
    /// new records read from the relay).
    private var listKey: String {
        listsIBKR
            ? ([liveFilter.rawValue, search, String(IBKRActivityStore.shared.items.count)] + quantRows.map(\.id)).joined(separator: "|")
            : rows.map(\.id).joined(separator: "|")
    }

    var body: some View {
        NavigationStack {
            PortSightList {
                if listsIBKR {
                    // The personal IBKR account's fills, orders (each folded into one line with its status
                    // changes), position changes and cash, by day; under 全部 the built-in quant rows follow.
                    Section {
                    } header: {
                        typePicker(selection: $liveFilter.animation(.smooth), options: IBKRActivityFilter.allCases, title: \.rawValue)
                    }
                    IBKRActivitySections(filter: liveFilter, search: search, showsEmptyState: quantRows.isEmpty)
                    if !quantRows.isEmpty {
                        Section {
                            ForEach(quantRows) { item in
                                NavigationLink { DemoActivityDetail(item: item) } label: { DemoActivityRow(item: item) }
                            }
                        } header: {
                            Text("量化账户")
                        } footer: { Text("入金和内部划转不计入投资收益。") }
                    }
                } else {
                    // Before pairing, the quant scope, or IBKR without records yet: the built-in rows.
                    Section {
                        if rows.isEmpty { ContentUnavailableView.search(text: search) }
                        ForEach(rows) { item in NavigationLink { DemoActivityDetail(item: item) } label: { DemoActivityRow(item: item) } }
                    } header: {
                        typePicker(selection: $filter.animation(.smooth), options: Self.builtInFilters, title: { $0 })
                    } footer: { Text("入金和内部划转不计入投资收益。") }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .contentMargins(.top, 4, for: .scrollContent)
            .portSightBackdrop()
            .animation(.smooth, value: listKey)
            .searchable(text: $search, prompt: "搜索交易、资金或系统事件")
            .toolbar { DemoToolbar() }
            .ordersDestination()
        }
    }

    /// The type picker as the first section's header: the full width of the cards, no inset of its own.
    private func typePicker<Value: Hashable>(selection: Binding<Value>, options: [Value],
                                             title: @escaping (Value) -> String) -> some View {
        Picker("类型", selection: selection) {
            ForEach(options, id: \.self) { Text(title($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
    }
}
struct DemoActivityDetail: View {
    @EnvironmentObject private var demo: PortfolioDemo
    let item: DemoActivity
    var body: some View {
        PortSightList {
            LabeledContent("事件", value: item.title)
            LabeledContent("来源", value: item.owner.rawValue)
            LabeledContent("时间", value: item.time)
            if let amount = item.amount { LabeledContent("金额", value: demoMoney(amount)) }
            Text(item.detail)
            // Before pairing every row is built in and says so; once paired the built-in rows (the quant account's)
            // stand beside the real IBKR records without a note.
            if !demo.isLive {
                Text("展示用记录，不对应真实成交或资金操作。").font(.caption).foregroundStyle(.secondary)
            }
        }.portSightBackdrop().navigationTitle("动态详情")
    }
}

struct DemoNotificationView: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @Environment(\.dismiss) private var dismiss
    @State private var severity = "全部"
    @State private var search = ""
    private var shownNotices: [DemoNotice] {
        demo.notices.filter { (severity == "全部" || $0.severity == severity) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        NavigationStack {
            List {
                HStack { Text(demo.scope.rawValue + "通知") }
                Picker("级别", selection: $severity) {
                    Text("全部").tag("全部"); Text("严重").tag("critical"); Text("警告").tag("warning"); Text("信息").tag("info")
                }.pickerStyle(.segmented)
                ForEach(shownNotices) { notice in
                    NavigationLink { DemoNoticeDetail(notice: notice) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(notice.severity == "critical" ? .red : notice.severity == "warning" ? .orange : .blue).frame(width: 7, height: 7).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(notice.title).fontWeight(demo.read.contains(notice.id) ? .regular : .semibold)
                                Text(notice.category + " · " + notice.time).font(.caption).foregroundStyle(.secondary)
                                if demo.acknowledged.contains(notice.id) { Label("已确认", systemImage: "checkmark.seal").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }.navigationTitle("通知").searchable(text: $search, prompt: "搜索通知")
                .animation(.smooth, value: shownNotices.map(\.id))
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}
/// One notice: its facts, 确认已查看 when it asks for it, and a button to where its link leads (RelayLink; an unknown
/// link gets no button). Relay notices come from GET /notices; the built-in ones keep their page as before.
struct DemoNoticeDetail: View {
    @EnvironmentObject private var demo: PortfolioDemo
    let notice: DemoNotice
    @State private var showsAsset = false

    private var link: RelayLink? { RelayLink(notice.link) }

    /// Relay notices ask for 确认已查看 only with requires_ack (and not once expired); built-in ones always offered it.
    private var asksAcknowledgement: Bool { notice.fromRelay ? notice.needsAcknowledgement() : true }

    /// asset:<symbol> opens that asset's page when the app has one; otherwise the link goes to 资产.
    private var linkedAsset: PortfolioAsset? {
        guard case .asset(let symbol) = link else { return nil }
        return NoticeAssets.asset(symbol)
    }

    private var footnote: String {
        if link == .ibkrReauth {
            // The banner follows IBKR's state alone: confirming this notice does not hide it.
            return "首页的重新授权横幅在 IBKR 重新连上后才会消失，与是否确认这条通知无关。"
        }
        if asksAcknowledgement { return "确认后首页的对应提示消失；不会修改任何策略或交易状态。" }
        return "通知只用于查看，App 不会修改任何策略或交易状态。"
    }

    var body: some View {
        MessageDetailLayout(
            severity: AlertSeverity(noticeSeverity: notice.severity),
            category: notice.category,
            categoryIcon: "bell",
            title: notice.title,
            detail: notice.detail,
            meta: [notice.owner.rawValue, notice.time],
            facts: notice.facts.map { .init(label: $0.label, value: $0.value) },
            link: link.map { link in .init(title: link.title, icon: link.icon) { follow(link) } },
            action: asksAcknowledgement
                ? .init(title: "确认已查看", doneTitle: "已确认", isDone: demo.acknowledged.contains(notice.id)) {
                    demo.acknowledged.insert(notice.id)
                }
                : nil,
            footnote: footnote)
        .onAppear { demo.read.insert(notice.id) }
        .navigationDestination(isPresented: $showsAsset) {
            if let linkedAsset { NoticeAssetPage(asset: linkedAsset) }
        }
    }

    private func follow(_ link: RelayLink) {
        if linkedAsset != nil {
            showsAsset = true
        } else {
            // 总览's banner, 服务器, 交易 · 复盘 / 理由卡, or 资产: ContentView closes this page and switches tabs.
            NoticeLinkRoute.shared.open(link)
        }
    }
}

/// The asset page a notice's asset:<symbol> link opens: the holding as the 持仓 page lists it.
enum NoticeAssets {
    static func asset(_ symbol: String) -> PortfolioAsset? {
        let symbol = symbol.uppercased()
        if DemoPortfolioData.enabled {
            // The holdings the pages show: built-in before pairing, the IBKR account's after.
            return Portfolio.combined(.all).first { $0.symbol.uppercased() == symbol }?.asset
        }
        let positions = CacheManager.load([Position].self, key: "positions_cache_v2") ?? []
        return positions.first { $0.displaySymbol.uppercased() == symbol }?.asPortfolioAsset
    }
}

/// AssetDetailView reads the market session from its environment; 消息中心 (a sheet) does not carry one.
private struct NoticeAssetPage: View {
    let asset: PortfolioAsset
    @StateObject private var marketVM: MarketStatusViewModel

    init(asset: PortfolioAsset) {
        self.asset = asset
        _marketVM = StateObject(wrappedValue: Self.market())
    }

    private static func market() -> MarketStatusViewModel {
        let market = MarketStatusViewModel()
        // The session from the New York clock, as 资产 shows it (DashboardView.applyDemo).
        if DemoPortfolioData.enabled { market.applyClock() }
        return market
    }

    var body: some View {
        AssetDetailView(asset: asset).environmentObject(marketVM)
    }
}

struct DemoStrategyDetail: View {
    // 交易 · 策略 shows the built-in strategies whether or not a relay is paired (no quant source on the relay yet).
    var body: some View { builtIn }
    private var builtIn: some View {
        PortSightList {
            Section("策略组合") {
                LabeledContent("核心 ETF 趋势", value: demoMoney(37950))
                LabeledContent("量化选股", value: demoMoney(4200))
                LabeledContent("策略现金", value: demoMoney(13000))
                LabeledContent("执行状态", value: "保护检查中")
            }
            Section("模型") {
                LabeledContent("冠军模型", value: "Alpha v3")
                LabeledContent("影子挑战者", value: "Alpha v4 · 观察第 12 天")
                LabeledContent("最新漂移提醒", value: "成交量特征分布变化 · 低等级")
                Text("挑战者只比较结果，不自动替换冠军。").font(.caption).foregroundStyle(.secondary)
            }
            Section("运行记录") {
                LabeledContent("最近运行", value: "10:32 · 完成")
                LabeledContent("数据新鲜度", value: "2 分钟前")
                LabeledContent("死信数量", value: "0")
                Text("此页面只展示监控状态，不提供交易、策略或风险参数操作。").font(.caption)
            }
        }.navigationTitle("量化策略")
    }
}

struct DemoReportDetail: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @State private var period = "月报"
    @State private var chart = "资产"
    private var points: [DemoPoint] {
        let all = curve
        return period == "日报" ? Array(all.suffix(2)) : period == "周报" ? Array(all.suffix(7)) : all
    }
    /// The scope's value history: the built-in curve, or once paired the real IBKR curve (个人 / 全部) when it has
    /// been read. The real curve has no benchmark, so it gets the built-in one: a steady 3.8 % over the month from
    /// the curve's start.
    private var curve: [DemoPoint] {
        let all = demo.points(demo.scope)
        guard Portfolio.hasRealHistory(demo.scope), all.count > 1, let start = all.first?.equity else { return all }
        return all.enumerated().map { index, point in
            DemoPoint(id: point.id, date: point.date, equity: point.equity,
                      benchmark: start * (1 + Double(index) / Double(all.count - 1) * 0.038), drawdown: point.drawdown)
        }
    }
    /// 入金 / 出金 in the real curve's month (none for the built-in curve).
    private var flowCount: Int {
        Portfolio.hasRealHistory(demo.scope) ? IBKREquityStore.shared.document(.standard)?.flows.count ?? 0 : 0
    }
    private var performance: Double {
        guard let first = points.first, let last = points.last, first.equity > 0 else { return 0 }
        return last.equity / first.equity - 1
    }
    var body: some View {
        List {
            HStack { Text(demo.scope.rawValue + "复盘") }
            Picker("周期", selection: $period) { ForEach(["日报", "周报", "月报"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
            Section {
                Text("\(period)收益 " + demoPercent(performance)).font(.title2.bold())
                Text("NVDA 和核心 ETF 提供主要正贡献。入金与内部划转单独记录。").foregroundStyle(.secondary)
                Picker("图表", selection: $chart) { Text("资产").tag("资产"); Text("收益率").tag("收益率") }.pickerStyle(.segmented)
                Chart {
                    ForEach(points) { point in
                        let first = points.first!
                        LineMark(x: .value("日期", point.date), y: .value("数值", chart == "资产" ? point.equity : (point.equity / first.equity - 1) * 100))
                            .foregroundStyle(by: .value("曲线", "账户"))
                        LineMark(x: .value("日期", point.date), y: .value("数值", chart == "资产" ? point.benchmark : (point.benchmark / first.benchmark - 1) * 100))
                            .foregroundStyle(by: .value("曲线", "基准"))
                    }
                }.frame(height: 210).chartForegroundStyleScale(["账户": Color.blue, "基准": Color.gray])
                Text(chart == "资产"
                     ? (flowCount > 0 ? "单位：USD · 期间有 \(flowCount) 笔入金或出金" : "单位：USD · 期间无外部现金流")
                     : "区间起点归零 · 单位：%").font(.caption).foregroundStyle(.secondary)
            }
            Section("风险与成本") {
                LabeledContent("区间最大回撤", value: demoPercent(points.map(\.drawdown).max() ?? 0))
                LabeledContent("换手率", value: "12.4%")
                LabeledContent("交易成本", value: "$8.40")
                Chart(points) { point in
                    AreaMark(x: .value("日期", point.date), y: .value("回撤 %", -point.drawdown * 100)).foregroundStyle(.orange.opacity(0.25))
                    LineMark(x: .value("日期", point.date), y: .value("回撤 %", -point.drawdown * 100)).foregroundStyle(.orange)
                }.frame(height: 110)
            }
        }.navigationTitle("复盘报告")
    }
}

struct DemoOwnershipLabel: View {
    @EnvironmentObject private var demo: PortfolioDemo
    let symbol: String
    private var lots: [DemoHolding] { demo.lots(demo.scope).filter { $0.symbol == symbol } }
    var body: some View {
        HStack(spacing: 7) {
            ForEach(lots) { lot in
                Text(lot.owner.rawValue + " " + lot.quantity.formatted(.number.precision(.fractionLength(0...4))))
                    .font(.caption2).foregroundStyle(lot.owner == .quant ? .orange : .blue)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background((lot.owner == .quant ? Color.orange : .blue).opacity(0.08), in: Capsule())
            }
        }
    }
}
/// The asset page's 持仓归属 / 模型建议 / 相关交易 cards. Once paired: the real lot and IBKR records where the relay
/// has them, the built-in lot, model advice and records everywhere else.
struct DemoAssetAdditions: View {
    @EnvironmentObject private var demo: PortfolioDemo
    let symbol: String
    var body: some View {
        VStack(spacing: 16) {
            DemoCard(title: "持仓归属", icon: "person.2") {
                DemoOwnershipLabel(symbol: symbol)
                ForEach(demo.lots(demo.scope).filter { $0.symbol == symbol }) { lot in
                    HStack { Text(lot.owner.rawValue); Spacer(); Text(demoMoney(lot.value)); Text("盈亏 " + demoMoney(lot.pnl)).foregroundStyle(lot.pnl >= 0 ? .green : .red) }.font(.subheadline)
                }
                Text("参考模型后手动买入，仍计入个人持仓。").font(.caption).foregroundStyle(.secondary)
            }
            NavigationLink { DemoAdviceDetail(symbol: symbol) } label: {
                DemoCard(title: "模型建议", icon: "sparkles") {
                    HStack { Text("评分 82 · 较上次 +4"); Spacer(); Image(systemName: "chevron.right") }
                    Text("查看 20/60 天区间、止盈止损、加减仓条件和近期事件").font(.caption).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain)
            DemoCard(title: "相关交易", icon: "clock") {
                let rows = demo.activities.filter { ($0.title + $0.detail).contains(symbol) }
                if rows.isEmpty { Text("暂无这项资产的交易记录").foregroundStyle(.secondary) }
                ForEach(rows) { DemoActivityRow(item: $0) }
            }
        }
    }
}
struct DemoInsightsAdditions: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @State private var symbol = ""
    @State private var hint = ""
    var body: some View {
        VStack(spacing: 16) {
            HStack { Text("模型与复盘").font(.title3.bold()) }
            NavigationLink { DemoReportDetail() } label: {
                DemoCard(title: "收益复盘", icon: "chart.xyaxis.line") {
                    HStack { Text("日报 / 周报 / 月报"); Spacer(); Image(systemName: "chevron.right") }
                    Text("账户与基准、回撤、换手和成本").font(.caption).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain)
            DemoCard(title: "自选与持仓建议", icon: "star") {
                HStack {
                    TextField("添加股票代码", text: $symbol).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Button("添加") {
                        let value = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        guard value.range(of: "^[A-Z][A-Z0-9.\\-]{0,11}$", options: .regularExpression) != nil else { hint = "请输入股票代码，例如 MSFT"; return }
                        if !demo.watchlist.contains(value) { demo.watchlist.append(value) }
                        symbol = ""; hint = ""
                    }
                }
                if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(.orange) }
                ForEach(demo.watchlist, id: \.self) { value in
                    HStack {
                        NavigationLink { DemoAdviceDetail(symbol: value) } label: {
                            HStack { Text(value).font(.subheadline.weight(.semibold)); Spacer(); Text("评分 82").foregroundStyle(.secondary); Image(systemName: "chevron.right").font(.caption) }
                        }.buttonStyle(.plain)
                        Button { demo.watchlist.removeAll { $0 == value } } label: { Image(systemName: "minus.circle").foregroundStyle(.secondary) }.accessibilityLabel("移除 " + value)
                    }.padding(.vertical, 5)
                }
                Text("新添加的代码展示统一模板，不生成真实预测。").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal).padding(.bottom, 30)
    }
}
/// The built-in model analysis of one symbol, paired or not (no AI analysis on the relay yet). Its reference
/// price is the holding's price: the real IBKR one once paired for a symbol held for real, else the built-in one.
struct DemoAdviceDetail: View {
    let symbol: String
    private var price: Double { Portfolio.lots(.all).first { $0.symbol == symbol }?.price ?? 100 }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack { Text(symbol).font(.largeTitle.bold()) }
                DemoCard(title: "模型评分", icon: "sparkles") {
                    HStack(alignment: .firstTextBaseline) { Text("82").font(.system(size: 40, weight: .bold)); Text("/100").foregroundStyle(.secondary); Spacer(); Text("↑ 4").foregroundStyle(.green) }
                    LabeledContent("池内排名", value: "第 12 / 500 · 上升 5 位")
                    Text("Alpha v3 · 模型输出").font(.caption).foregroundStyle(.secondary)
                }
                DemoCard(title: "预期与区间", icon: "chart.line.uptrend.xyaxis") {
                    forecast("未来 20 个交易日", expected: "+3.2%", range: "−6.0% ~ +12.0%")
                    Divider()
                    forecast("未来 60 个交易日", expected: "+8.4%", range: "−12.0% ~ +24.0%")
                    Text("80% 预测区间，不能视为保证收益。").font(.caption).foregroundStyle(.secondary)
                }
                DemoCard(title: "价格条件", icon: "flag.2.crossed") {
                    LabeledContent("参考价格", value: demoMoney(price))
                    LabeledContent("止损参考", value: demoMoney(price * 0.92))
                    LabeledContent("止盈参考", value: demoMoney(price * 1.15))
                    LabeledContent("历史先触止盈 / 止损", value: "58% / 27%")
                    LabeledContent("观察期内均未触及", value: "15%")
                }
                DemoCard(title: "仓位与行动条件", icon: "slider.horizontal.3") {
                    Text("加仓：突破观察区间并维持两日，成交量同步增加。")
                    Text("历史胜率：61% · 124 个样本").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("减仓：跌破趋势线，或合并敞口超过预设目标。")
                    Text("历史胜率：56% · 98 个样本").font(.caption).foregroundStyle(.secondary)
                    LabeledContent("建议仓位", value: "5%")
                }
                DemoCard(title: "近期事件", icon: "calendar") {
                    Label("财报 · 未来一周的提醒", systemImage: "doc.text")
                    Label("内部人交易 · 记录待核实", systemImage: "person.text.rectangle")
                    Text("增发、13D 和财报重述也将在此展示。").font(.caption).foregroundStyle(.secondary)
                }
                Text("成本假设为单边 0.10%。建议仅供参考，App 不会下单。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding()
        }.background(.ultraThinMaterial).navigationTitle("建议详情")
    }
    private func forecast(_ title: String, expected: String, range: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title); Spacer(); Text(expected).foregroundStyle(.green).fontWeight(.semibold) }
            Text("区间 " + range).font(.caption).foregroundStyle(.secondary)
        }
    }
}
