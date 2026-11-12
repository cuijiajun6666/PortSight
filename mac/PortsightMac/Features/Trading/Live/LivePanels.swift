import SwiftUI
import PortSightKit

enum LiveBottomTab: String, CaseIterable, Identifiable {
    case positions = "当前持仓", orders = "当前委托", fills = "历史成交", funds = "资金"
    var id: String { rawValue }
}

/// The exchange-style panel under the chart: positions, working orders, fill history and the account's money.
/// Clicking a position or a fill shows its trade on the chart. Nothing here can trade.
struct LiveBottomPanel: View {
    @Bindable var model: LiveViewerModel
    @Binding var tab: LiveBottomTab
    @State private var fillSort = [KeyPathComparator(\LiveFill.t, order: .reverse)]
    @State private var fillContract: String?
    @State private var fillSide: BacktestSide?
    @State private var selectedFill: LiveFill.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                DesktopCapsulePicker(title: "面板", options: LiveBottomTab.allCases, selection: $tab) { title($0) }.fixedSize().labelsHidden()
                Spacer()
                if tab == .fills { fillFilters }
            }
            switch tab {
            case .positions: positionsTable
            case .orders: ordersTable
            case .fills: fillsTable
            case .funds: funds
            }
        }
        // A filter from another account or model could match nothing (and leave the Picker without a matching tag).
        .onChange(of: model.accountKind) { resetFillFilters() }
        .onChange(of: model.modelFilter) { resetFillFilters() }
        .onChange(of: model.contractCounts.map(\.contract)) { _, contracts in
            if let contract = fillContract, !contracts.contains(contract) { fillContract = nil }
        }
    }

    private func resetFillFilters() {
        fillContract = nil
        fillSide = nil
    }

    private func title(_ item: LiveBottomTab) -> String {
        switch item {
        case .positions: "当前持仓 \(model.positions.count)"
        case .orders: "当前委托 \(model.openOrders.count)"
        case .fills: "历史成交 \(model.fills.count)"
        case .funds: "资金"
        }
    }

    private func sideTint(_ side: BacktestSide) -> Color { side == .long ? DesktopTheme.green : .red }
    private func orderTint(_ side: LiveOrderSide) -> Color { side == .buy ? DesktopTheme.green : .red }

    // MARK: Positions

    private var positionsTable: some View {
        let rows = model.positions
        return Table(rows, selection: Binding(get: { model.selectedPosition?.id }, set: { id in
            if let id, let position = rows.first(where: { $0.id == id }) { model.focus(position) }
        })) {
            TableColumn("合约") { position in
                VStack(alignment: .leading, spacing: 1) {
                    Text(position.contractTitle).fontWeight(.medium)
                    Text(position.tradeId).font(.system(size: 10)).foregroundStyle(.secondary).monospaced()
                }
            }
            .width(min: 120, ideal: 130)
            TableColumn("方向") { position in
                Text(position.side.title + " " + String(format: "%.0f×", position.leverage)).foregroundStyle(sideTint(position.side))
            }
            .width(54)
            TableColumn("数量") { Text(LiveFormat.size($0.size) + " 张").monospacedDigit() }.width(min: 70, ideal: 80)
            TableColumn("开仓均价") { Text(LiveFormat.price($0.entryPx)).monospacedDigit() }.width(min: 76, ideal: 84)
            TableColumn("标记价") { position in
                Text(LiveFormat.price(position.markPx)).monospacedDigit()
                    .contentTransition(.numericText(value: position.markPx))
            }
            .width(min: 76, ideal: 84)
            TableColumn("强平价") { Text($0.liquidationPx.map(LiveFormat.price) ?? "—").monospacedDigit().foregroundStyle(.secondary) }
                .width(min: 76, ideal: 84)
            TableColumn("未实现盈亏") { position in
                VStack(alignment: .leading, spacing: 1) {
                    Text(LiveFormat.signedMoney(position.unrealizedPnl))
                        .contentTransition(.numericText(value: position.unrealizedPnl))
                    Text(BacktestFormat.percent(position.unrealizedPct)).font(.system(size: 10))
                        .contentTransition(.numericText(value: position.unrealizedPct))
                }
                .monospacedDigit().foregroundStyle(DesktopTheme.pnlColor(position.unrealizedPnl))
                .animation(.smooth(duration: 0.3), value: position.unrealizedPnl)
            }
            .width(min: 90, ideal: 100)
            TableColumn("止损 / 止盈") { position in
                Text((position.stopPx.map(LiveFormat.price) ?? "—") + " / " + (position.targetPx.map(LiveFormat.price) ?? "—"))
                    .monospacedDigit()
            }
            .width(min: 120, ideal: 140)
            TableColumn("开仓时间") { Text(LiveFormat.time($0.openedAt)).monospacedDigit() }.width(min: 100, ideal: 110)
            TableColumn("模型") { Text($0.model) }.width(min: 64, ideal: 72)
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { if rows.isEmpty { empty("没有持仓") } }
    }

    // MARK: Orders

    private var ordersTable: some View {
        let rows = model.openOrders
        return Table(rows) {
            TableColumn("时间") { Text(LiveFormat.time($0.updatedAt)).monospacedDigit() }.width(min: 100, ideal: 110)
            TableColumn("合约") { Text(LiveFormat.contractTitle($0.contract)) }.width(min: 110, ideal: 120)
            TableColumn("类型") { Text($0.type.title) }.width(50)
            TableColumn("方向") { order in
                Text(order.actionTitle + " · " + order.side.title).foregroundStyle(orderTint(order.side))
            }
            .width(min: 80, ideal: 90)
            TableColumn("价格") { Text($0.price.map(LiveFormat.price) ?? "市价").monospacedDigit() }.width(min: 76, ideal: 84)
            TableColumn("数量") { Text(LiveFormat.size($0.size) + " 张").monospacedDigit() }.width(min: 70, ideal: 80)
            TableColumn("已成交") { Text(LiveFormat.size($0.filled)).monospacedDigit() }.width(56)
            TableColumn("状态") { order in
                Text(order.status.title + (order.reduceOnly ? " · 只减仓" : "")).foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 110)
            TableColumn("模型") { Text($0.model) }.width(min: 64, ideal: 72)
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { if rows.isEmpty { empty("没有等待中的委托") } }
    }

    // MARK: Fills

    private var fillFilters: some View {
        HStack(spacing: 10) {
            DesktopCapsuleMenu(title: "合约", value: fillContract ?? "全部合约", selection: $fillContract) {
                Text("全部合约").tag(String?.none)
                ForEach(model.contractCounts, id: \.contract) { Text($0.contract).tag(String?.some($0.contract)) }
            }
            .fixedSize()
            DesktopCapsuleMenu(title: "方向", value: fillSide?.title ?? "多空", selection: $fillSide) {
                Text("多空").tag(BacktestSide?.none)
                Text("多").tag(BacktestSide?.some(.long))
                Text("空").tag(BacktestSide?.some(.short))
            }
            .fixedSize()
        }
        .labelsHidden()
        .controlSize(.small)
    }

    private var fillsTable: some View {
        let rows = model.fills
            .filter { (fillContract == nil || $0.contract == fillContract) && (fillSide == nil || $0.positionSide == fillSide) }
            .sorted(using: fillSort)
        return VStack(alignment: .leading, spacing: 8) {
            Table(rows, selection: Binding(get: { selectedFill }, set: { id in
                selectedFill = id
                if let id, let fill = rows.first(where: { $0.id == id }) { model.focus(fill: fill) }
            }), sortOrder: $fillSort) {
                TableColumn("时间", value: \.t) { Text(LiveFormat.time($0.t)).monospacedDigit() }.width(min: 100, ideal: 110)
                TableColumn("合约", value: \.contract).width(min: 70, ideal: 80)
                TableColumn("方向", value: \.actionTitle) { fill in
                    Text(fill.actionTitle).foregroundStyle(orderTint(fill.side))
                }
                .width(44)
                TableColumn("价格", value: \.price) { Text(LiveFormat.price($0.price)).monospacedDigit() }.width(min: 76, ideal: 84)
                TableColumn("数量", value: \.size) { Text(LiveFormat.size($0.size) + " 张").monospacedDigit() }.width(min: 66, ideal: 76)
                TableColumn("手续费", value: \.fee) { Text(LiveFormat.money($0.fee)).monospacedDigit().foregroundStyle(.secondary) }
                    .width(min: 56, ideal: 64)
                TableColumn("已实现盈亏", value: \.realizedPnl) { fill in
                    if fill.action == .open || fill.action == .add {
                        Text("—").foregroundStyle(.secondary)
                    } else {
                        Text(LiveFormat.signedMoney(fill.realizedPnl)).monospacedDigit()
                            .foregroundStyle(DesktopTheme.pnlColor(fill.realizedPnl))
                    }
                }
                .width(min: 80, ideal: 90)
                TableColumn("原因", value: \.reason) { Text($0.reasonTitle) }.width(min: 60, ideal: 70)
                TableColumn("交易", value: \.tradeId) { Text($0.tradeId).monospaced().foregroundStyle(.secondary) }
                    .width(min: 90, ideal: 100)
                TableColumn("模型", value: \.model).width(min: 64, ideal: 72)
            }
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { if rows.isEmpty { empty("没有成交") } }
            Text("\(rows.count) 笔成交 · 点击一行，K 线跳到那笔交易").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    // MARK: Funds

    private var funds: some View {
        let account = model.account
        let fills = model.fills
        let todayStart = (model.feed.now / 86_400_000).rounded(.down) * 86_400_000
        let today = fills.filter { $0.t >= todayStart }
        let realized = model.trades.reduce(0) { $0 + $1.realizedPnl - $1.fee }
        return Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 10) {
            GridRow {
                fund("钱包余额", account?.balance)
                fund("权益", account?.equity)
                fund("可用", account?.available)
                fund("保证金占用", account?.marginUsed)
            }
            GridRow {
                fund("未实现盈亏", account?.unrealizedPnl, signed: true)
                fund("今日盈亏", account?.todayPnl, signed: true)
                fund("今日手续费", account?.todayFee)
                fund("已平仓交易净盈亏", realized, signed: true)
            }
            GridRow {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日成交").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(today.count) 笔").font(.system(size: 15, weight: .medium)).monospacedDigit()
                        .contentTransition(.numericText(value: Double(today.count)))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("已平仓交易").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(model.trades.count) 笔").font(.system(size: 15, weight: .medium)).monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("币种").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(account?.currency ?? "USDT").font(.system(size: 15, weight: .medium))
                }
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesktopTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.smooth(duration: 0.35), value: account?.equity)
    }

    private func fund(_ label: String, _ value: Double?, signed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value.map { signed ? LiveFormat.signedMoney($0) : LiveFormat.money($0) } ?? "—")
                .font(.system(size: 15, weight: .medium)).monospacedDigit()
                .foregroundStyle(signed ? DesktopTheme.pnlColor(value ?? 0) : .primary)
                .contentTransition(.numericText(value: value ?? 0))
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary).allowsHitTesting(false)
    }
}

/// One card per model: state, last and next run, signal counts, latest signals and checks.
/// For the shadow ledger `showsSignals` is false: state, counts and checks only.
struct LiveModelCards: View {
    let models: [LiveModelStatus]
    let showsSignals: Bool
    let now: Double

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
            ForEach(models) { status in card(status) }
        }
    }

    private func stateColor(_ state: LiveModelState) -> Color {
        switch state {
        case .running: DesktopTheme.green
        case .paused: .secondary
        case .error: .red
        }
    }

    private func card(_ status: LiveModelStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(status.model).font(.system(size: 14, weight: .semibold))
                Spacer()
                HStack(spacing: 5) {
                    DesktopStatusDot(color: stateColor(status.state))
                    Text(status.state.title)
                }
                .font(.system(size: 11, weight: .medium)).foregroundStyle(stateColor(status.state))
            }
            if let message = status.message {
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.red)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                row("上次运行", status.lastRun.map(LiveFormat.time) ?? "—")
                row("下次运行", status.nextRun.map { LiveFormat.time($0) + "（" + countdown($0) + "）" } ?? "—")
                row("信号次数", "今日 \(status.signalsToday) · 累计 \(status.signalsTotal)")
                row("合约", status.contracts.joined(separator: " · "))
            }
            .font(.system(size: 12)).monospacedDigit()
            if showsSignals && !status.signals.isEmpty {
                Divider()
                Text("最新信号").font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(status.signals.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key).monospaced()
                        Spacer()
                        Text(String(format: "%+.4f", status.signals[key] ?? 0)).monospacedDigit()
                            .contentTransition(.numericText(value: status.signals[key] ?? 0))
                    }
                    .font(.system(size: 11))
                }
            }
            Divider()
            HStack {
                Text("检查").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text("\(status.passedChecks) / \(status.checks.count) 过").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(status.checks) { check in
                HStack(spacing: 6) {
                    Image(systemName: check.pass ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(check.pass ? DesktopTheme.green : .red)
                    Text(check.name)
                    Spacer()
                    if let detail = check.detail { Text(detail).foregroundStyle(.secondary).monospacedDigit() }
                    Text(check.title).fontWeight(.medium).foregroundStyle(check.pass ? DesktopTheme.green : .red)
                }
                .font(.system(size: 11))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(DesktopTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DesktopTheme.border, lineWidth: 1) }
    }

    private func countdown(_ t: Double) -> String {
        let seconds = max(0, Int((t - now) / 1_000))
        return seconds >= 60 ? "\(seconds / 60) 分 \(seconds % 60) 秒后" : "\(seconds) 秒后"
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}
