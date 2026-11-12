import SwiftUI
import PortSightKit

/// Keeps the 实时 page's feed and state while other sections are on screen. The feed is built off the main thread
/// (LiveFeed.shared(), warmed up after launch), so opening 交易 does not stall.
@Observable
final class DesktopLiveStore {
    private(set) var model: LiveViewerModel?

    func load() async {
        let feed = await LiveFeed.shared()
        if model == nil { model = LiveViewerModel(feed: feed) }
    }
}

/// The 实时 page once its feed is ready. Paired or not it shows the built-in feed (the relay has no source for the
/// quant system's accounts yet); the trade card's 交易理由 read the relay's 理由卡 (TradeReasonPanel, JournalStore).
struct DesktopLivePage: View {
    let store: DesktopLiveStore

    var body: some View {
        if let model = store.model {
            DesktopLiveTradingView(model: model)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await store.load() }
        }
    }
}

/// 交易 · 实时: what a model is doing right now on the 模拟盘 or 实盘 account, and what it did before, like an
/// exchange's trading screen. Read-only: there is no control that places, cancels or changes an order.
/// The 影子账本 is sealed (forward seal from 2026-10-22): only status, signal counts and checks.
struct DesktopLiveTradingView: View {
    @Bindable var model: LiveViewerModel
    @State private var toast: LiveEvent?
    @State private var bottomTab: LiveBottomTab = .positions
    /// Width of the chart row, nil until measured (the card then starts beside the chart, the usual case).
    @State private var chartRowWidth: CGFloat?

    private var feed: LiveFeed { model.feed }

    var body: some View {
        DesktopFullPage(maxWidth: 1_400, spacing: 24) {
            header
            if model.showsMoney {
                accountStrip
                chartSection
                LiveBottomPanel(model: model, tab: $bottomTab)
            } else {
                Label("影子账本在前向封存期：只显示运行状态、信号次数和检查结果，不显示收益、持仓和净值。结果 \(LiveFeed.shadowUnsealDate) 开封。",
                      systemImage: "lock.fill")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            DesktopPageSection(title: "模型状态", subtitle: model.showsMoney ? "每 5 分钟运行一次" : "只显示状态、信号次数和检查") {
                LiveModelCards(models: model.visibleModels, showsSignals: model.showsMoney, now: feed.now)
            }
            Text("只读：这里只显示量化系统报告的账户、持仓、委托和成交。App 不下单、不撤单、不改单，也不保存交易所密钥。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        // The feed is shared (one per app, also across windows): this page is one of its clients.
        .onAppear { feed.start(for: ObjectIdentifier(model)) }
        .onDisappear { feed.stop(for: ObjectIdentifier(model)) }
        .onChange(of: feed.lastEvent?.seq) { _, _ in showLatestEvent() }
        .task(id: toast?.seq) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { withAnimation(.smooth) { toast = nil } }
        }
    }

    /// A banner for the newest model action on the account (and model) on screen.
    private func showLatestEvent() {
        guard let event = feed.lastEvent, model.showsMoney, event.accountId == model.account?.id,
              feed.now - event.t < 10_000 else { return }
        let eventModel = event.fill?.model ?? event.order?.model
        if let filter = model.modelFilter, eventModel != filter { return }
        withAnimation(.smooth) { toast = event }
    }

    // MARK: Header

    private var header: some View {
        let running = model.accountModels.filter { $0.state == .running }.count
        let detail = "\(model.accountModels.count) 个模型 · \(running) 个运行中 · 更新于 " + LiveFormat.clock(feed.now)
        return DesktopPageHeader(eyebrow: "交易 · 实时", title: model.account?.name ?? model.accountKind.title, detail: detail) {
            HStack(spacing: 10) {
                DesktopCapsulePicker(title: "账户", options: LiveAccountKind.allCases, selection: $model.accountKind) { $0.title }.fixedSize().labelsHidden()
                Menu {
                    Picker("模型", selection: $model.modelFilter) {
                        Text("全部模型").tag(String?.none)
                        ForEach(model.accountModels) { Text($0.model).tag(String?.some($0.model)) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(model.modelFilter ?? "全部模型", systemImage: "cpu")
                }
                .fixedSize()
                if model.showsMoney { contractPicker }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
    }

    /// Every contract the account (and model) traded: segments for a few, a menu with trade counts for more.
    @ViewBuilder private var contractPicker: some View {
        let counts = model.contractCounts
        let selection = Binding(get: { model.contract }, set: { model.changeContract($0) })
        if counts.count <= 5 {
            DesktopCapsulePicker(title: "合约", options: counts.map(\.contract), selection: selection) { $0 }.fixedSize().labelsHidden()
        } else {
            DesktopCapsuleMenu(title: "合约", value: selection.wrappedValue, selection: selection) {
                ForEach(counts, id: \.contract) { Text("\($0.contract)  ·  \($0.count) 笔").tag($0.contract) }
            }.fixedSize().labelsHidden()
        }
    }

    // MARK: Account

    private var accountStrip: some View {
        let account = model.account
        let currency = account?.currency ?? "USDT"
        let equity = account?.equity ?? 0
        // With a model filter, money figures stay account-wide (labelled 账户) and 未实现盈亏 covers that model only.
        let scoped = model.modelFilter != nil
        let prefix = scoped ? "账户" : ""
        let positions = model.positions
        let unrealized = scoped ? positions.reduce(0) { $0 + $1.unrealizedPnl } : (account?.unrealizedPnl ?? 0)
        return HStack(alignment: .top, spacing: 24) {
            LiveStat(label: prefix + "权益", value: equity, text: LiveFormat.money(equity), unit: currency)
            LiveStat(label: prefix + "可用", value: account?.available ?? 0, text: LiveFormat.money(account?.available ?? 0), unit: currency)
            LiveStat(label: prefix + "保证金占用", value: account?.marginUsed ?? 0, text: LiveFormat.money(account?.marginUsed ?? 0),
                     unit: equity > 0 ? BacktestFormat.plainPercent((account?.marginUsed ?? 0) / equity) : nil)
            LiveStat(label: prefix + "今日盈亏", value: account?.todayPnl ?? 0, text: LiveFormat.signedMoney(account?.todayPnl ?? 0),
                     unit: equity > 0 ? BacktestFormat.percent((account?.todayPnl ?? 0) / equity) : nil,
                     tint: DesktopTheme.pnlColor(account?.todayPnl ?? 0))
            LiveStat(label: scoped ? "模型未实现盈亏" : "未实现盈亏", value: unrealized, text: LiveFormat.signedMoney(unrealized),
                     unit: "\(positions.count) 个持仓", tint: DesktopTheme.pnlColor(unrealized))
        }
    }

    // MARK: Chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DesktopCapsulePicker(title: "周期", options: LiveViewerModel.timeframes, selection: Binding(get: { model.timeframe }, set: { model.changeTimeframe($0) })) { $0.shortTitle }.fixedSize().labelsHidden()
                HStack(spacing: 5) {
                    DesktopStatusDot(color: feed.isRunning ? DesktopTheme.green : .secondary)
                    Text(feed.isRunning ? "实时" : "已暂停")
                    Text("内置数据 · 尚未接入量化系统").foregroundStyle(.tertiary)
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                legend
                ControlGroup {
                    Button { model.zoom(by: 1.4, around: nil) } label: { Image(systemName: "minus.magnifyingglass") }
                        .help("缩小")
                    Button { model.zoom(by: 1 / 1.4, around: nil) } label: { Image(systemName: "plus.magnifyingglass") }
                        .help("放大")
                    Button { model.showAll() } label: { Image(systemName: "arrow.left.and.right") }
                        .help("显示全部")
                }
                .fixedSize()
            }

            // The selected trade's card sits beside the chart when the chart keeps at least minChartWidth, else under
            // it. One layout switches, so the card (its unfolded reasons, its scroll) stays the same view either way.
            let beside = (chartRowWidth ?? .infinity) >= Self.minChartWidth + 14 + Self.cardWidth
            let layout = beside ? AnyLayout(HStackLayout(alignment: .top, spacing: 14))
                                : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            layout {
                chartBox
                if let card = tradeCard() {
                    card.frame(width: beside ? Self.cardWidth : nil)
                        .transition(.move(edge: beside ? .trailing : .top).combined(with: .opacity))
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { chartRowWidth = $0 }
            .animation(.smooth(duration: 0.25), value: model.selectedTradeID)

            Text("每笔交易一个框，持仓中的框一直画到现在并标出浮动盈亏 · 图表跟随最新 K 线，拖动后点 回到最新 · 点击框或下方表格看详情 · 双指左右滑平移 · 按住 ⌘ 上下滑缩放")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private static let chartHeight: CGFloat = 440
    /// The trade card beside the chart: figures on the left, 交易理由 on the right.
    private static let cardWidth: CGFloat = 640
    private static let minChartWidth: CGFloat = 460

    private var chartBox: some View {
        TradeChart(model: model)
            .frame(height: Self.chartHeight)
            .padding(14)
            .background(DesktopTheme.card, in: DesktopTheme.surfaceShape)
            .overlay { DesktopTheme.surfaceShape.strokeBorder(DesktopTheme.border, lineWidth: 1) }
            .overlay(alignment: .top) {
                if let toast, let headline = toast.headline {
                    LiveToast(event: toast, headline: headline)
                        .padding(.top, 52)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
    }

    /// The selected open position or closed trade; nil when nothing (or a trade no longer listed) is selected.
    private func tradeCard() -> LiveTradeCard? {
        let position = model.selectedPosition
        let record = position == nil ? model.selectedRecord : nil
        guard position != nil || record != nil else { return nil }
        return LiveTradeCard(model: model, position: position, record: record, height: Self.chartHeight + 28) {
            model.selectedTradeID = nil
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            swatch(DesktopTheme.green.opacity(0.35), "盈利区")
            swatch(Color.red.opacity(0.35), "亏损区")
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
    }

    private func swatch(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title)
        }
    }
}

/// A key figure of the account strip; the number rolls when it changes.
private struct LiveStat: View {
    let label: String
    let value: Double
    let text: String
    var unit: String? = nil
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText(value: value))
            if let unit {
                Text(unit).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    .monospacedDigit().contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.35), value: value)
    }
}

/// "v4 G263 开多 BTCUSDT 0.12 张 @ 68,420.5", shown for a few seconds when a model acts.
private struct LiveToast: View {
    let event: LiveEvent
    let headline: String

    private var tint: Color {
        if let fill = event.fill { return fill.side == .buy ? DesktopTheme.green : .red }
        if let order = event.order { return order.side == .buy ? DesktopTheme.green : .red }
        return .secondary
    }

    private var icon: String {
        if let fill = event.fill {
            return fill.action == .open || fill.action == .add ? "plus.circle.fill" : "minus.circle.fill"
        }
        return "clock.badge.checkmark.fill"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(headline).fontWeight(.medium).monospacedDigit()
            Text(LiveFormat.clock(event.t)).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
