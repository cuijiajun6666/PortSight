//
//  TerminalLiveTradingView.swift
//  PortSight
//
//  交易 · 实时 on iPhone: the Mac 实时 page on the same PortSightKit model (LiveViewerModel over LiveFeed).
//  The 账户 menu (模拟盘 · 实盘 · 影子账本) in the toolbar left of the bell, model / contract menus, the account strip, the live K-line with trade and position boxes, the newest
//  model action, then 持仓 · 委托 · 成交 · 资金. Tapping a row shows its trade on the chart and opens its details.
//  Read-only: there is no control that places, cancels or changes an order, and no keys.
//  The 影子账本 is sealed (forward seal from 2026-10-22): status, signal counts and checks only.
//

import SwiftUI
import Charts
import PortSightKit

/// Builds the live model once, on first visit (KeptAlivePages re-creates this struct on every page switch). The feed
/// itself is built off the main thread (LiveFeed.shared(), warmed up after launch), so opening 交易 does not stall.
/// `isActive` is false while another 交易 page is in front; the feed's clock only runs while the page is on screen.
struct TerminalLiveTradingView: View {
    var isActive = true
    @State private var model: LiveViewerModel?

    var body: some View {
        if let model {
            TerminalLiveContent(model: model, isActive: isActive)
        } else {
            NavigationStack {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .portSightBackdrop()
                    .toolbar { DemoToolbar(showsScope: false) }
            }
            // Usually the feed is built by now: the page then shows in the same update, with no spinner frame.
            // (Not in body or init: reading the feed there would make the parent re-render on every tick.)
            .onAppear {
                if model == nil, let feed = LiveFeed.ready { model = LiveViewerModel(feed: feed) }
            }
            .task {
                let feed = await LiveFeed.shared()
                if model == nil { model = LiveViewerModel(feed: feed) }
            }
        }
    }
}

/// 交易 · 实时 drawn once where nobody sees it, soon after launch (ContentView), with its clock off. The first time
/// SwiftUI shows a view type it does one-time work for it (type lookups, reflection, layout and list set-up, the
/// chart's marks); for this page that was most of half a second on the main thread, felt as a stall the first time
/// 交易 was opened. Afterwards opening 交易 costs about what any other tab does.
struct TradingWarmUp: View {
    /// Once per launch: the one-time work is per process, and opening 交易 does it as well.
    static var done = false

    var body: some View {
        TradingTabView(page: .constant(.live), isActive: false)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The four lists under the chart.
private enum LiveListTab: String, CaseIterable, Identifiable {
    case positions = "持仓", orders = "委托", fills = "成交", funds = "资金"
    var id: String { rawValue }
}

/// The trade a detail sheet shows (an open position or a closed trade), by trade ID.
private struct LiveDetailItem: Identifiable {
    let id: String
}

private struct TerminalLiveContent: View {
    @Bindable var model: LiveViewerModel
    let isActive: Bool

    @Environment(\.scenePhase) private var scenePhase
    @State private var onScreen = false
    @State private var tab: LiveListTab = .positions
    @State private var detail: LiveDetailItem?
    @State private var fillContract: String?
    @State private var fillSide: BacktestSide?
    @State private var fillLimit = 40

    private static let chartID = "live-kline"
    private var feed: LiveFeed { model.feed }
    private var currency: String { model.account?.currency ?? "USDT" }
    private var shouldRun: Bool { isActive && onScreen && scenePhase == .active }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                PortSightList {
                    heroSection
                    if model.showsMoney {
                        accountSection
                        chartSection
                            .id(Self.chartID)
                        bannerSection
                        listSection { tradeID in
                            withAnimation(.smooth) { scroller.scrollTo(Self.chartID, anchor: .top) }
                            if let tradeID { detail = LiveDetailItem(id: tradeID) }
                        }
                    } else {
                        sealSection
                    }
                    modelsSection
                }
                .terminalPageList()
                .toolbar {
                    // 账户 (模拟盘 · 实盘 · 影子账本) just left of the bell, as 订单 is on the 资产 tab.
                    DemoToolbar(showsScope: false, showsBell: false)
                    ToolbarItem(placement: .topBarTrailing) { accountMenu.padding(.horizontal, 6) }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    MessageCenterToolbar()
                }
                .animation(.smooth, value: model.accountKind)
                .animation(.smooth, value: tab)
                .sensoryFeedback(.selection, trigger: model.accountKind)
                .sensoryFeedback(.selection, trigger: model.contract)
                .sensoryFeedback(.selection, trigger: tab)
                .sheet(item: $detail) { item in
                    TerminalLiveTradeSheet(model: model, tradeID: item.id)
                        .presentationDetents([.medium, .large])
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                }
            }
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .onChange(of: shouldRun, initial: true) { _, run in
            // The feed is shared: this page is one of its clients (the clock stops when none is on screen).
            if run { feed.start(for: ObjectIdentifier(model)) } else { feed.stop(for: ObjectIdentifier(model)) }
        }
        .onChange(of: model.accountKind) { fillContract = nil; fillSide = nil; fillLimit = 40 }
    }

    // MARK: Header

    private var heroSection: some View {
        let running = model.accountModels.filter { $0.state == .running }.count
        let account = model.account
        let eyebrow = model.showsMoney ? (account?.name ?? model.accountKind.title) + " · 权益（\(currency)）"
                                       : model.accountKind.title + " · 运行状态"
        let value = model.showsMoney ? LiveFormat.money(account?.equity ?? 0) : "\(running) / \(model.accountModels.count) 运行中"
        let detail = "\(model.accountModels.count) 个模型 · \(running) 个运行中 · 更新于 " + LiveFormat.clock(feed.now)
        return Section {
            TerminalHero(eyebrow: eyebrow, value: value, detail: detail) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        modelMenu
                        if model.showsMoney { contractMenu }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .font(.subheadline.weight(.medium))
                    // The glass rim draws just outside each capsule; keep the first one inside the row, which clips.
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .terminalHeroRow()
        }
    }

    /// The toolbar's 账户 menu (left of the bell): the current account's symbol and name, styled like the page menu.
    private var accountMenu: some View {
        Menu {
            Picker("账户", selection: $model.accountKind) {
                ForEach(LiveAccountKind.allCases) { kind in
                    Label(kind.title, systemImage: icon(kind)).tag(kind)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon(model.accountKind))
                    .contentTransition(.symbolEffect(.replace))
                Text(model.accountKind.title)
                    .contentTransition(.interpolate)
            }
            .font(.subheadline.weight(.semibold))
            .animation(.smooth, value: model.accountKind)
        }
        .accessibilityLabel("账户：" + model.accountKind.title)
    }

    private func icon(_ kind: LiveAccountKind) -> String {
        switch kind {
        case .paper: "testtube.2"
        case .live: "bolt.fill"
        case .shadow: "lock.fill"
        }
    }

    private var modelMenu: some View {
        Menu {
            Picker("模型", selection: $model.modelFilter) {
                Text("全部模型").tag(String?.none)
                ForEach(model.accountModels) { Text($0.model).tag(String?.some($0.model)) }
            }
            .pickerStyle(.inline)
        } label: {
            menuLabel(model.modelFilter ?? "全部模型", systemImage: "cpu")
        }
        .accessibilityLabel("模型：" + (model.modelFilter ?? "全部模型"))
    }

    /// Every contract the account (and model) traded or holds, with its trade count.
    private var contractMenu: some View {
        Menu {
            Picker("合约", selection: Binding(get: { model.contract }, set: { model.changeContract($0) })) {
                ForEach(model.contractCounts, id: \.contract) { item in
                    Text("\(item.contract) · \(item.count) 笔").tag(item.contract)
                }
            }
            .pickerStyle(.inline)
        } label: {
            // The contract's coin, its real icon (SymbolLogoStore) in place of the generic coin symbol.
            HStack(spacing: 0) {
                SymbolLogoView(symbol: model.contract, crypto: true, size: 16)
                    .padding(.trailing, 4)
                Text(model.contract)
            }
        }
        .accessibilityLabel("合约：" + model.contract)
    }

    private func menuLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 0) {
            Image(systemName: systemImage)
            Text(title)
        }
    }

    // MARK: Account

    private var accountSection: some View {
        let account = model.account
        let equity = account?.equity ?? 0
        return Section {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    LiveStatCell(label: "可用", value: account?.available ?? 0,
                                 text: LiveFormat.money(account?.available ?? 0), unit: currency)
                    LiveStatCell(label: "保证金占用", value: account?.marginUsed ?? 0,
                                 text: LiveFormat.money(account?.marginUsed ?? 0),
                                 unit: equity > 0 ? "占权益 " + BacktestFormat.plainPercent((account?.marginUsed ?? 0) / equity) : nil)
                }
                GridRow {
                    LiveStatCell(label: "今日盈亏", value: account?.todayPnl ?? 0,
                                 text: LiveFormat.signedMoney(account?.todayPnl ?? 0),
                                 unit: equity > 0 ? BacktestFormat.percent((account?.todayPnl ?? 0) / equity) : nil,
                                 tint: TerminalStyle.pnl(account?.todayPnl ?? 0))
                    LiveStatCell(label: "未实现盈亏", value: account?.unrealizedPnl ?? 0,
                                 text: LiveFormat.signedMoney(account?.unrealizedPnl ?? 0),
                                 unit: "\(model.positions.count) 个持仓", tint: TerminalStyle.pnl(account?.unrealizedPnl ?? 0))
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Chart

    private var chartSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Picker("周期", selection: Binding(get: { model.timeframe }, set: { model.changeTimeframe($0) })) {
                        ForEach(LiveViewerModel.timeframes) { Text($0.shortTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    zoomButtons
                }
                TerminalLiveChart(model: model) { tradeID in detail = LiveDetailItem(id: tradeID) }
                    .frame(height: 320)
                legend
            }
            .padding(.vertical, 6)
        } header: {
            HStack(spacing: 5) {
                Text("K 线")
                Circle().fill(feed.isRunning ? Color.green : Color.secondary).frame(width: 6, height: 6)
                Text(feed.isRunning ? "实时" : "已暂停")
            }
        } footer: {
            Text("每笔交易一个框，持仓中的框一直画到现在并标出浮动盈亏。图表跟随最新 K 线，左右拖动后点 回到最新。捏合缩放，点框看详情。")
        }
    }

    private var zoomButtons: some View {
        HStack(spacing: 4) {
            Button { withAnimation(.smooth) { model.zoom(by: 1.4, around: nil) } } label: { Image(systemName: "minus.magnifyingglass") }
                .accessibilityLabel("缩小")
            Button { withAnimation(.smooth) { model.zoom(by: 1 / 1.4, around: nil) } } label: { Image(systemName: "plus.magnifyingglass") }
                .accessibilityLabel("放大")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.small)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            swatch(.green.opacity(0.35), "盈利区")
            swatch(.red.opacity(0.35), "亏损区")
            swatch(.blue.opacity(0.55), "仓位")
            Spacer(minLength: 0)
            Text("内置数据 · 尚未接入量化系统").foregroundStyle(.tertiary)
        }
        .font(.caption2).foregroundStyle(.secondary)
        .lineLimit(1).minimumScaleFactor(0.8)
    }

    private func swatch(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title)
        }
    }

    // MARK: Newest action

    /// The newest thing a model of this account (and model filter) did since the page opened; before that, its
    /// newest fill. Highlighted for ten seconds after it happens.
    private var bannerSection: some View {
        let accountID = model.account?.id
        let filter = model.modelFilter
        let event = feed.recentEvents.last { event in
            guard event.accountId == accountID, event.headline != nil else { return false }
            let eventModel = event.fill?.model ?? event.order?.model
            return filter == nil || eventModel == filter
        }
        let fallback = event == nil ? model.fills.first : nil
        let fresh = event.map { feed.now - $0.t < 10_000 } ?? false
        return Section {
            if let event, let headline = event.headline {
                LiveBannerRow(headline: headline, time: event.t, side: event.fill?.side ?? event.order?.side,
                              icon: bannerIcon(event), fresh: fresh)
                    .id(event.seq)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let fill = fallback {
                LiveBannerRow(headline: fill.headline, time: fill.t, side: fill.side,
                              icon: fill.action == .open || fill.action == .add ? "plus.circle.fill" : "minus.circle.fill",
                              fresh: false)
            } else {
                Text("还没有成交").foregroundStyle(.secondary)
            }
        } header: {
            Text("最新动作")
        }
        .animation(.smooth, value: event?.seq)
        .sensoryFeedback(.impact(weight: .light), trigger: event?.seq)
    }

    private func bannerIcon(_ event: LiveEvent) -> String {
        if let fill = event.fill {
            return fill.action == .open || fill.action == .add ? "plus.circle.fill" : "minus.circle.fill"
        }
        return "clock.badge.checkmark.fill"
    }

    // MARK: Lists

    /// `focus` scrolls to the chart and, with a trade ID, opens that trade's details.
    private func listSection(focus: @escaping (String?) -> Void) -> some View {
        Section {
            switch tab {
            case .positions: positionRows(focus: focus)
            case .orders: orderRows(focus: focus)
            case .fills: fillRows(focus: focus)
            case .funds: fundRows
            }
        } header: {
            VStack(alignment: .leading, spacing: 12) {
                Picker("列表", selection: $tab) {
                    ForEach(LiveListTab.allCases) { Text(title($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, -4)
                HStack {
                    Text(header(tab))
                    Spacer()
                    if tab == .fills { fillFilterMenu }
                }
            }
            .textCase(nil)
        } footer: {
            Text("点一行，K 线跳到那笔交易并打开详情。只读：这里只显示量化系统报告的账户、持仓、委托和成交。App 不下单、不撤单、不改单，也不保存交易所密钥。")
        }
    }

    private func title(_ item: LiveListTab) -> String {
        switch item {
        case .positions: "持仓 \(model.positions.count)"
        case .orders: "委托 \(model.openOrders.count)"
        case .fills: "成交"
        case .funds: "资金"
        }
    }

    private func header(_ item: LiveListTab) -> String {
        switch item {
        case .positions: "当前持仓"
        case .orders: "当前委托"
        case .fills: "历史成交 · \(filteredFills.count) 笔"
        case .funds: "资金"
        }
    }

    @ViewBuilder
    private func positionRows(focus: @escaping (String?) -> Void) -> some View {
        let rows = model.positions
        if rows.isEmpty {
            Text("没有持仓").foregroundStyle(.secondary)
        }
        ForEach(rows) { position in
            Button {
                model.focus(position)
                focus(position.tradeId)
            } label: {
                LivePositionRow(position: position, selected: position.tradeId == model.selectedTradeID)
            }
            .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func orderRows(focus: @escaping (String?) -> Void) -> some View {
        let rows = model.openOrders
        if rows.isEmpty {
            Text("没有等待中的委托").foregroundStyle(.secondary)
        }
        ForEach(rows) { order in
            Button {
                if let tradeID = order.tradeId, let position = feed.positions.first(where: { $0.tradeId == tradeID }) {
                    model.focus(position)
                    focus(tradeID)
                } else {
                    model.changeContract(order.contract)
                    focus(nil)
                }
            } label: {
                LiveOrderRow(order: order)
            }
            .foregroundStyle(.primary)
        }
    }

    private var filteredFills: [LiveFill] {
        model.fills.filter { (fillContract == nil || $0.contract == fillContract) && (fillSide == nil || $0.positionSide == fillSide) }
    }

    @ViewBuilder
    private func fillRows(focus: @escaping (String?) -> Void) -> some View {
        let rows = filteredFills
        if rows.isEmpty {
            Text("没有成交").foregroundStyle(.secondary)
        }
        ForEach(rows.prefix(fillLimit)) { fill in
            Button {
                model.focus(fill: fill)
                focus(fill.tradeId)
            } label: {
                LiveFillRow(fill: fill, selected: fill.tradeId == model.selectedTradeID)
            }
            .foregroundStyle(.primary)
        }
        if rows.count > fillLimit {
            Button("再显示 \(min(40, rows.count - fillLimit)) 笔") { fillLimit += 40 }
        }
    }

    private var fillFilterMenu: some View {
        Menu {
            Picker("合约", selection: $fillContract) {
                Text("全部合约").tag(String?.none)
                ForEach(model.contractCounts, id: \.contract) { Text($0.contract).tag(String?.some($0.contract)) }
            }
            Picker("方向", selection: $fillSide) {
                Text("多空").tag(BacktestSide?.none)
                Text("多").tag(BacktestSide?.some(.long))
                Text("空").tag(BacktestSide?.some(.short))
            }
        } label: {
            Label("筛选", systemImage: fillContract == nil && fillSide == nil
                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .labelStyle(.iconOnly)
                .font(.body)
        }
        .textCase(nil)
    }

    @ViewBuilder
    private var fundRows: some View {
        let account = model.account
        // UTC day, like the kit's todayPnl / todayFee / signalsToday and the Mac app.
        let todayStart = (feed.now / 86_400_000).rounded(.down) * 86_400_000
        let today = model.fills.filter { $0.t >= todayStart }.count
        let realized = model.trades.reduce(0) { $0 + $1.realizedPnl - $1.fee }
        Group {
            fund("钱包余额", account?.balance)
            fund("权益", account?.equity)
            fund("可用", account?.available)
            fund("保证金占用", account?.marginUsed)
            fund("未实现盈亏", account?.unrealizedPnl, signed: true)
            fund("今日盈亏", account?.todayPnl, signed: true)
            fund("今日手续费", account?.todayFee)
            fund("已平仓交易净盈亏", realized, signed: true)
            LabeledContent("今日成交") {
                Text("\(today) 笔").contentTransition(.numericText(value: Double(today)))
            }
            LabeledContent("已平仓交易", value: "\(model.trades.count) 笔")
            LabeledContent("币种", value: currency)
        }
        .monospacedDigit()
    }

    private func fund(_ label: String, _ value: Double?, signed: Bool = false) -> some View {
        LabeledContent(label) {
            Text(value.map { signed ? LiveFormat.signedMoney($0) : LiveFormat.money($0) } ?? "—")
                .foregroundStyle(signed ? TerminalStyle.pnl(value ?? 0) : .primary)
                .contentTransition(.numericText(value: value ?? 0))
                .animation(.smooth(duration: 0.3), value: value)
        }
    }

    // MARK: Shadow ledger

    private var sealSection: some View {
        Section {
            Label {
                Text("影子账本在前向封存期：只显示运行状态、信号次数和检查结果，不显示收益、持仓和净值。结果 \(LiveFeed.shadowUnsealDate) 开封。")
            } icon: {
                Image(systemName: "lock.fill").foregroundStyle(.purple)
            }
            .font(.subheadline)
        }
    }

    // MARK: Models

    @ViewBuilder
    private var modelsSection: some View {
        let models = model.visibleModels
        if models.isEmpty {
            Section("模型状态") { Text("没有模型").foregroundStyle(.secondary) }
        }
        ForEach(Array(models.enumerated()), id: \.element.id) { index, status in
            Section {
                LiveModelRows(status: status, showsSignals: model.showsMoney, now: feed.now)
            } header: {
                if index == 0 {
                    Text(model.showsMoney ? "模型状态 · 每 5 分钟运行一次" : "模型状态 · 只显示状态、信号次数和检查")
                }
            } footer: {
                if index == models.count - 1 && !model.showsMoney {
                    Text("只读：App 不下单、不撤单、不改单，也不保存交易所密钥。")
                }
            }
        }
    }
}

// MARK: - Rows

/// A key figure of the account strip; the number rolls when it changes.
private struct LiveStatCell: View {
    let label: String
    let value: Double
    let text: String
    var unit: String? = nil
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(text).font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText(value: value))
            if let unit {
                Text(unit).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    .monospacedDigit().contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.35), value: value)
        .accessibilityElement(children: .combine)
    }
}

/// "v4 G263 开多 BTCUSDT 0.12 张 @ 68,420.5" with its time.
private struct LiveBannerRow: View {
    let headline: String
    let time: Double
    let side: LiveOrderSide?
    let icon: String
    let fresh: Bool

    private var tint: Color {
        switch side {
        case .buy: .green
        case .sell: .red
        case nil: .secondary
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.subheadline.weight(.medium)).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                Text(LiveFormat.time(time)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
            if fresh {
                Text("新").font(.caption2.weight(.semibold)).foregroundStyle(tint)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(tint.opacity(0.14), in: Capsule())
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: fresh)
        .accessibilityElement(children: .combine)
    }
}

private struct LivePositionRow: View {
    let position: LivePosition
    let selected: Bool

    var body: some View {
        let tint = TerminalStyle.pnl(position.unrealizedPnl)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(position.contractTitle).font(.subheadline.weight(.semibold))
                Text(position.side.title + " " + String(format: "%.0f×", position.leverage))
                    .font(.caption.weight(.semibold)).foregroundStyle(position.side == .long ? .green : .red)
                if selected {
                    Image(systemName: "scope").font(.caption).foregroundStyle(.blue).accessibilityLabel("K 线上正在看")
                }
                Spacer(minLength: 4)
                Text(LiveFormat.signedMoney(position.unrealizedPnl)).font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText(value: position.unrealizedPnl))
            }
            HStack(spacing: 6) {
                Text(LiveFormat.size(position.size) + " 张 · 开 " + LiveFormat.price(position.entryPx) + " · 标记 "
                     + LiveFormat.price(position.markPx))
                    .contentTransition(.numericText(value: position.markPx))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(BacktestFormat.percent(position.unrealizedPct)).foregroundStyle(tint)
                    .contentTransition(.numericText(value: position.unrealizedPct))
            }
            .font(.caption).foregroundStyle(.secondary)
            Text("止损 " + (position.stopPx.map(LiveFormat.price) ?? "—") + " · 止盈 " + (position.targetPx.map(LiveFormat.price) ?? "—")
                 + " · " + position.model)
                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
        .monospacedDigit()
        .padding(.vertical, 2)
        .animation(.smooth(duration: 0.3), value: position.unrealizedPnl)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct LiveOrderRow: View {
    let order: LiveOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(order.contract).font(.subheadline.weight(.semibold))
                Text(order.type.title + " · " + order.actionTitle).font(.caption.weight(.semibold))
                    .foregroundStyle(order.side == .buy ? .green : .red)
                Spacer(minLength: 4)
                Text(order.price.map(LiveFormat.price) ?? "市价").font(.subheadline.weight(.medium))
            }
            HStack(spacing: 6) {
                Text(LiveFormat.size(order.size) + " 张 · 已成交 " + LiveFormat.size(order.filled) + " · " + order.status.title
                     + (order.reduceOnly ? " · 只减仓" : ""))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(LiveFormat.time(order.updatedAt))
            }
            .font(.caption).foregroundStyle(.secondary)
            Text(order.model).font(.caption2).foregroundStyle(.tertiary)
        }
        .monospacedDigit()
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct LiveFillRow: View {
    let fill: LiveFill
    let selected: Bool

    var body: some View {
        let closes = fill.action == .reduce || fill.action == .close
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(fill.contract).font(.subheadline.weight(.semibold))
                Text(fill.actionTitle).font(.caption.weight(.semibold)).foregroundStyle(fill.side == .buy ? .green : .red)
                Text(fill.reasonTitle).font(.caption).foregroundStyle(.secondary)
                if selected {
                    Image(systemName: "scope").font(.caption).foregroundStyle(.blue).accessibilityLabel("K 线上正在看")
                }
                Spacer(minLength: 4)
                if closes {
                    Text(LiveFormat.signedMoney(fill.realizedPnl)).font(.subheadline.weight(.medium))
                        .foregroundStyle(TerminalStyle.pnl(fill.realizedPnl))
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Text(LiveFormat.price(fill.price) + " × " + LiveFormat.size(fill.size) + " 张 · 手续费 " + LiveFormat.money(fill.fee))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(LiveFormat.time(fill.t))
            }
            .font(.caption).foregroundStyle(.secondary)
            Text(fill.model + " · " + fill.tradeId).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
        .monospacedDigit()
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One model: state, last and next run, signal counts, latest signals and checks. For the shadow ledger
/// `showsSignals` is false: state, counts and checks only.
private struct LiveModelRows: View {
    let status: LiveModelStatus
    let showsSignals: Bool
    let now: Double

    private var stateColor: Color {
        switch status.state {
        case .running: .green
        case .paused: .secondary
        case .error: .red
        }
    }

    var body: some View {
        HStack {
            Text(status.model).font(.headline)
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(stateColor).frame(width: 7, height: 7)
                Text(status.state.title)
            }
            .font(.subheadline.weight(.medium)).foregroundStyle(stateColor)
        }
        if let message = status.message {
            Label(message, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
        }
        Group {
            LabeledContent("上次运行", value: status.lastRun.map(LiveFormat.time) ?? "—")
            LabeledContent("下次运行") {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(status.nextRun.map(LiveFormat.time) ?? "—")
                    if let next = status.nextRun {
                        Text(countdown(next)).font(.caption).foregroundStyle(.secondary)
                            .contentTransition(.numericText(countsDown: true))
                    }
                }
            }
            LabeledContent("信号次数") {
                Text("今日 \(status.signalsToday) · 累计 \(status.signalsTotal)")
                    .contentTransition(.numericText(value: Double(status.signalsTotal)))
            }
            LabeledContent("合约", value: status.contracts.joined(separator: " · "))
        }
        .monospacedDigit()
        if showsSignals && !status.signals.isEmpty {
            ForEach(status.signals.keys.sorted(), id: \.self) { key in
                LabeledContent {
                    Text(String(format: "%+.4f", status.signals[key] ?? 0)).monospacedDigit()
                        .contentTransition(.numericText(value: status.signals[key] ?? 0))
                } label: {
                    Text(key).monospaced().font(.subheadline)
                }
            }
        }
        DisclosureGroup {
            ForEach(status.checks) { check in
                HStack(spacing: 8) {
                    Image(systemName: check.pass ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(check.pass ? .green : .red)
                    Text(check.name).font(.subheadline)
                    Spacer()
                    if let detail = check.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                    }
                    Text(check.title).font(.subheadline.weight(.medium)).foregroundStyle(check.pass ? .green : .red)
                }
                .accessibilityElement(children: .combine)
            }
        } label: {
            LabeledContent("检查") {
                Text("\(status.passedChecks) / \(status.checks.count) 过")
                    .foregroundStyle(status.passedChecks == status.checks.count ? .green : .orange)
                    .monospacedDigit()
            }
        }
    }

    private func countdown(_ t: Double) -> String {
        let seconds = max(0, Int((t - now) / 1_000))
        return seconds >= 60 ? "\(seconds / 60) 分 \(seconds % 60) 秒后" : "\(seconds) 秒后"
    }
}

// MARK: - Detail sheet

/// One trade of a paper or live account: an open position (live profit, updating) or a closed trade. Looks the
/// trade up by ID on every update, so a position that closes while the sheet is open turns into its closed trade.
private struct TerminalLiveTradeSheet: View {
    let model: LiveViewerModel
    let tradeID: String
    @Environment(\.dismiss) private var dismiss
    /// Pairing again (or unpairing) restarts the 交易理由 reading at once.
    @ObservedObject private var server = ServerStore.shared

    private var feed: LiveFeed { model.feed }

    /// Money accounts only: the shadow ledger never has positions or trades, and is checked again here.
    private func visible(_ accountID: String) -> Bool { feed.account(id: accountID)?.kind.showsMoney == true }

    private var position: LivePosition? {
        feed.positions.first { $0.tradeId == tradeID && visible($0.accountId) }
    }

    private var record: LiveTradeRecord? {
        feed.closedTrades.first { $0.trade.id == tradeID && visible($0.accountId) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let position {
                    positionList(position)
                } else if let record {
                    recordList(record)
                } else {
                    ContentUnavailableView("找不到这笔交易", systemImage: "questionmark.circle")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(title).font(.headline)
                        Text(tradeID).font(.caption2).foregroundStyle(.secondary).monospaced()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        // The 交易理由 part at the bottom (GET /journal): read on opening, then every few minutes while open.
        .task(id: server.pairingState) {
            while !Task.isCancelled {
                await JournalStore.shared.load()
                try? await Task.sleep(for: .seconds(JournalStore.freshFor))
            }
        }
    }

    private var title: String {
        if let position { return position.contractTitle + " · " + position.side.title + " · 持仓中" }
        if let record { return LiveFormat.contractTitle(record.trade.symbol) + " · " + record.trade.side.title }
        return "交易"
    }

    private func currency(_ accountID: String) -> String { feed.account(id: accountID)?.currency ?? "USDT" }

    /// Bars for the path chart: the finest timeframe whose bars reach back to the entry with a few bars inside.
    private func pathBars(_ trade: BacktestTrade) -> [BacktestBar] {
        for timeframe in LiveFeed.timeframes {
            let bars = feed.bars(trade.symbol, timeframe)
            guard let first = bars.first, first.t <= trade.entryT else { continue }
            let low = BacktestViewerModel.index(in: bars, atOrBefore: trade.entryT)
            let high = BacktestViewerModel.index(in: bars, atOrBefore: trade.exitT)
            if high - low >= 3 && high - low <= 600 { return bars }
        }
        return feed.bars(trade.symbol, .h1)
    }

    private var fills: [LiveFill] { feed.fills.filter { $0.tradeId == tradeID } }

    // MARK: Open position

    private func positionList(_ position: LivePosition) -> some View {
        let tint = TerminalStyle.pnl(position.unrealizedPnl)
        let trade = position.chartTrade(now: feed.now, equity: feed.account(id: position.accountId)?.equity ?? 1)
        return PortSightList {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("未实现盈亏（\(currency(position.accountId))）· 按保证金 " + BacktestFormat.percent(position.unrealizedPct))
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        .contentTransition(.numericText(value: position.unrealizedPct))
                    Text(LiveFormat.signedMoney(position.unrealizedPnl))
                        .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(tint)
                        .contentTransition(.numericText(value: position.unrealizedPnl))
                }
                .animation(.smooth(duration: 0.3), value: position.unrealizedPnl)
                .listRowBackground(Color.clear)
                // A little room at the top keeps the first line clear of the section's rounded corner.
                .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 8, trailing: 4))
            }

            pathSection(trade, isOpen: true)

            Section {
                TradeFigureGrid(figures: [
                    TradeFigure("数量", LiveFormat.size(position.size) + " 张 · " + String(format: "%.0f×", position.leverage)),
                    TradeFigure("开仓均价", LiveFormat.price(position.entryPx)),
                    TradeFigure("标记价", LiveFormat.price(position.markPx)),
                    TradeFigure("强平价", position.liquidationPx.map(LiveFormat.price) ?? "—"),
                    TradeFigure("止损", position.stopPx.map(LiveFormat.price) ?? "—"),
                    TradeFigure("止盈", position.targetPx.map(LiveFormat.price) ?? "—"),
                    TradeFigure("保证金", LiveFormat.money(position.margin)),
                    TradeFigure("已实现", LiveFormat.signedMoney(position.realizedPnl), tint: TerminalStyle.pnl(position.realizedPnl)),
                    TradeFigure("手续费", LiveFormat.money(position.fee)),
                    TradeFigure("持有", BacktestFormat.hours((feed.now - position.openedAt) / 3_600_000)),
                    TradeFigure("开仓", LiveFormat.time(position.openedAt)),
                    TradeFigure("模型", position.model),
                ])
            }

            changesSections(trade)
            fillsSection
            TradeReasonSection(symbol: position.contract, side: position.side, tradeID: position.tradeId, start: position.openedAt, end: feed.now)
        }
        .listStyle(.insetGrouped)
        // The content starts right under the bar: no top margin.
        .listSectionSpacing(.compact)
        .contentMargins(.top, 0, for: .scrollContent)
    }

    // MARK: Closed trade

    private func recordList(_ record: LiveTradeRecord) -> some View {
        let trade = record.trade
        let net = record.realizedPnl - record.fee
        return PortSightList {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("净盈亏（\(currency(record.accountId))）· 占权益 " + BacktestFormat.percent(trade.pnlNet, digits: 3))
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    Text(LiveFormat.signedMoney(net))
                        .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(TerminalStyle.pnl(net))
                        .contentTransition(.numericText(value: net))
                }
                .listRowBackground(Color.clear)
                // A little room at the top keeps the first line clear of the section's rounded corner.
                .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 8, trailing: 4))
            }

            pathSection(trade, isOpen: false)

            Section {
                TradeFigureGrid(figures: [
                    TradeFigure("开仓价", LiveFormat.price(trade.entryPx)),
                    TradeFigure("平仓价", LiveFormat.price(trade.exitPx)),
                    TradeFigure("开仓", LiveFormat.time(trade.entryT)),
                    TradeFigure("平仓", LiveFormat.time(trade.exitT)),
                    TradeFigure("持有", BacktestFormat.hours(trade.holdH)),
                    TradeFigure("价格变动", BacktestFormat.percent(trade.priceReturn)),
                    TradeFigure("已实现", LiveFormat.signedMoney(record.realizedPnl), tint: TerminalStyle.pnl(record.realizedPnl)),
                    TradeFigure("手续费", LiveFormat.money(record.fee)),
                    TradeFigure("最大浮盈", BacktestFormat.percent(trade.mfe, digits: 3)),
                    TradeFigure("最大浮亏", BacktestFormat.percent(trade.mae, digits: 3)),
                    TradeFigure("平仓原因", trade.exitTitle),
                    TradeFigure("模型", record.model),
                ])
            }

            if !trade.signalsAtEntry.isEmpty {
                Section("开仓时信号") {
                    ForEach(trade.signalsAtEntry.keys.sorted(), id: \.self) { key in
                        LabeledContent {
                            Text(String(format: "%.4f", trade.signalsAtEntry[key] ?? 0)).monospacedDigit()
                        } label: {
                            Text(key).monospaced()
                        }
                    }
                }
            }

            changesSections(trade)
            fillsSection
            TradeReasonSection(symbol: trade.symbol, side: trade.side, tradeID: trade.id, start: trade.entryT, end: trade.exitT)
        }
        .listStyle(.insetGrouped)
        // The content starts right under the bar: no top margin.
        .listSectionSpacing(.compact)
        .contentMargins(.top, 0, for: .scrollContent)
    }

    // MARK: Shared sections

    @ViewBuilder
    private func pathSection(_ trade: BacktestTrade, isOpen: Bool) -> some View {
        let bars = pathBars(trade)
        if !bars.isEmpty {
            Section {
                TerminalLivePathChart(trade: trade, bars: bars, isOpen: isOpen)
                    .frame(height: 180)
                    .padding(.vertical, 6)
            } header: {
                Text("价格与止损")
            } footer: {
                Text("红色虚线是止损，绿色虚线是止盈（提前结束处的绿点是半仓止盈），蓝色是仓位。")
            }
        }
    }

    @ViewBuilder
    private func changesSections(_ trade: BacktestTrade) -> some View {
        if !trade.stops.isEmpty {
            Section("止损移动") { levelRows(trade.stops) }
        }
        if !trade.targets.isEmpty {
            Section("止盈") { levelRows(trade.targets) }
        }
        if !trade.sizePath.isEmpty {
            Section("仓位变化") {
                ForEach(Array(trade.sizePath.sorted { $0.t < $1.t }.enumerated()), id: \.offset) { _, step in
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("占权益 " + BacktestFormat.plainPercent(abs(step.w)))
                            Text(LiveFormat.time(step.t)).font(.caption).foregroundStyle(.secondary)
                        }
                        .monospacedDigit()
                    } label: {
                        Text(step.title)
                    }
                }
            }
        }
    }

    private func levelRows(_ levels: [BacktestLevel]) -> some View {
        ForEach(Array(levels.sorted { $0.t < $1.t }.enumerated()), id: \.offset) { index, level in
            LabeledContent {
                Text(LiveFormat.price(level.px)).monospacedDigit()
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(index == 0 ? "初始" : "第 \(index) 次移动")
                    Text(LiveFormat.time(level.t)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private var fillsSection: some View {
        let rows = fills
        if !rows.isEmpty {
            Section("成交 · \(rows.count) 笔") {
                ForEach(rows.reversed()) { fill in
                    LiveFillRow(fill: fill, selected: false)
                }
            }
        }
    }
}

// MARK: - Figures two to a row

/// One figure of the trade sheet: a small label over its value.
struct TradeFigure {
    let label: String
    let value: String
    var tint: Color = .primary

    init(_ label: String, _ value: String, tint: Color = .primary) {
        self.label = label
        self.value = value
        self.tint = tint
    }
}

/// The trade sheet's figures two to a row (like the Mac trade card), in one list row.
struct TradeFigureGrid: View {
    let figures: [TradeFigure]
    /// At accessibility text sizes one figure per row, so values are not cut.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let perRow = typeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: figures.count, by: perRow).map { Array(figures[$0..<min($0 + perRow, figures.count)]) }
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, figure in cell(figure) }
                    if row.count < perRow { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func cell(_ figure: TradeFigure) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(figure.label).font(.caption).foregroundStyle(.secondary)
            Text(figure.value).font(.subheadline).monospacedDigit()
                .foregroundStyle(figure.tint)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
