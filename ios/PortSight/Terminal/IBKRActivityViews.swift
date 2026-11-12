//
//  IBKRActivityViews.swift
//  PortSight
//
//  The personal IBKR account's activity once paired (IBKRActivityStore, GET /ibkr/activity): the 动态 list (orders
//  folded into one line each, fills, cash movements, position changes, by day), an order's status changes
//  (submitted → partially filled → filled / cancelled, tied together by perm_id), a record's details, the cash
//  totals, and the 订单 page's list. Times are shown in the phone's time zone.
//

import SwiftUI
import PortSightKit

// MARK: - 动态 list

/// The sections of the 动态 list for `filter` and `search`, inside a List. Shows the store's state when there is
/// nothing to list, and reads older pages when the end of the list comes into view.
struct IBKRActivitySections: View {
    let filter: IBKRActivityFilter
    let search: String
    /// False when other rows follow (the built-in quant rows under 全部): nothing is said about an empty list.
    var showsEmptyState = true

    var body: some View {
        let store = IBKRActivityStore.shared
        let entries = IBKRActivityList.timeline(store.items, filter: filter, search: search)
        if filter == .cash, search.isEmpty, !store.items.isEmpty {
            IBKRCashSummarySection(items: store.items)
        }
        if entries.isEmpty, showsEmptyState {
            Section {
                if !search.isEmpty, !store.items.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else if store.phase.isLoading, store.items.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    ContentUnavailableView(emptyTitle,
                                           systemImage: "clock.arrow.circlepath",
                                           description: store.phase.placeholder()?.detail.map { Text($0) })
                }
            }
        }
        ForEach(IBKRActivityList.byDay(entries), id: \.day) { group in
            Section(IBKRActivityList.dayTitle(group.day)) {
                ForEach(group.entries) { entry in
                    NavigationLink { IBKRTimelineDestination(entry: entry) } label: { IBKRTimelineRow(entry: entry) }
                }
            }
        }
        if !entries.isEmpty {
            Section {
                if !store.reachedStart {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .task(id: store.items.count) { await store.loadOlder() }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let saved = IBKRActivityText.savedNote(store) { Text(saved) }
                    if store.reachedStart { Text("IBKR 只提供 2026 年 5 月 14 日以后的报表，这里已是全部记录。") }
                }
            }
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .all: "还没有交易记录"
        case .trades: "还没有成交或委托"
        case .cash: "还没有资金流水"
        case .positions: "还没有持仓变化"
        }
    }
}

/// One line: an order (its latest status), or a single record. An order, fill or position change of a stock or
/// coin leads with that asset's real icon (its status or direction as a small badge); everything else with its icon.
struct IBKRTimelineRow: View {
    let entry: IBKRTimelineEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leadingIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.subheadline.weight(.medium))
                Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                Text(IBKRActivityText.clock(entry.date) + source).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 5)
            if let amount {
                Text(IBKRActivity.money(amount, currency))
                    .font(.subheadline).monospacedDigit()
                    .foregroundStyle(amount > 0 ? Color.green : Color.primary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var leadingIcon: some View {
        if let logo {
            SymbolLogoView(symbol: logo.symbol, crypto: logo.crypto, size: 32)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 15, height: 15)
                        .background(.regularMaterial, in: Circle())
                        .offset(x: 3, y: 3)
                }
        } else {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(.primary.opacity(0.05), in: Circle())
        }
    }

    /// The stock or coin this line is about (orders, fills, position changes); nil for cash, currency pairs and
    /// anything logo.dev cannot have an icon for (options and the like).
    private var logo: (symbol: String, crypto: Bool)? {
        let record: IBKRActivity?
        switch entry {
        case .order(let history): record = history.unitSource
        case .record(let item): record = item.kind == .fill || item.kind == .order || item.kind == .position ? item : nil
        }
        guard let record, let symbol = entry.symbol, record.sec_type?.uppercased() != "CASH" else { return nil }
        let crypto = record.sec_type?.uppercased() == "CRYPTO" || SymbolLogoStore.isCrypto(symbol)
        guard SymbolLogoStore.key(symbol, crypto: crypto) != nil else { return nil }
        return (symbol, crypto)
    }

    private var icon: String {
        switch entry {
        case .order(let history): IBKRActivityText.statusIcon(history.latest)
        case .record(let item):
            switch item.kind {
            case .fill: item.isBuy ? "arrow.down.left" : "arrow.up.right"
            case .cash: IBKRCashType(item.type).icon
            case .position: "chart.bar.doc.horizontal"
            case .order: IBKRActivityText.statusIcon(item)
            case .other: "circle"
            }
        }
    }

    private var tint: Color {
        switch entry {
        case .order(let history): IBKRActivityText.statusTint(history.latest)
        case .record: .primary
        }
    }

    /// Money that moved: a fill's value, the fills of an order, a cash amount.
    private var amount: Double? {
        switch entry {
        case .order(let history):
            history.fills.isEmpty ? nil : history.fills.reduce(0) { $0 + ($1.signedValue ?? 0) }
        case .record(let item):
            item.kind == .fill ? item.signedValue : item.kind == .cash ? item.amount : nil
        }
    }

    private var currency: String? {
        switch entry {
        case .order(let history): history.fills.first?.currency ?? history.latest?.currency
        case .record(let item): item.currency
        }
    }

    private var source: String {
        switch entry {
        case .order(let history): history.steps.contains { $0.isRealtime } ? "" : " · 报表"
        case .record(let item): item.isRealtime ? "" : " · 报表"
        }
    }
}

struct IBKRTimelineDestination: View {
    let entry: IBKRTimelineEntry

    var body: some View {
        switch entry {
        case .order(let history): IBKROrderHistoryView(permID: history.id)
        case .record(let item): IBKRActivityDetail(item: item)
        }
    }
}

// MARK: - An order's life

/// Every status the order went through, oldest first, and its fills.
struct IBKROrderHistoryView: View {
    let permID: String

    var body: some View {
        let history = IBKRActivityList.order(permID, in: IBKRActivityStore.shared.items)
        PortSightList {
            if let history {
                Section {
                    LabeledContent("代码", value: history.symbol ?? "—")
                    LabeledContent("方向", value: history.isBuy ? "买入" : "卖出")
                    if let type = history.latest?.order_type { LabeledContent("类型", value: IBKRActivity.orderTypeTitle(type)) }
                    if let quantity = history.quantity { LabeledContent("委托数量", value: IBKRActivity.quantityText(abs(quantity)) + " 股") }
                    if history.filledQuantity > 0 {
                        LabeledContent("已成交", value: IBKRActivity.quantityText(history.filledQuantity) + " 股")
                    }
                    if let limit = history.steps.last(where: { $0.limit_price != nil })?.limit_price {
                        LabeledContent("限价", value: IBKRActivity.money(limit, history.latest?.currency))
                    }
                    if !history.fills.isEmpty, let average = history.averagePrice {
                        LabeledContent("成交均价", value: IBKRActivity.money(average, history.fills.first?.currency))
                    }
                    LabeledContent("状态") {
                        Text(history.latest?.statusTitle ?? "—").foregroundStyle(IBKRActivityText.statusTint(history.latest))
                    }
                }

                Section("状态变化") {
                    ForEach(history.steps) { step in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: IBKRActivityText.statusIcon(step))
                                .foregroundStyle(IBKRActivityText.statusTint(step))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.statusTitle ?? "更新").font(.subheadline.weight(.medium))
                                Text(step.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 5)
                            Text(IBKRActivityText.dateTime(step.date)).font(.caption2).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                if !history.fills.isEmpty {
                    Section("成交") {
                        ForEach(history.fills) { fill in
                            // Opened from this order: its "状态变化" link goes back here instead of stacking another copy.
                            NavigationLink { IBKRActivityDetail(item: fill, openedFromOrder: permID) } label: { IBKRTimelineRow(entry: .record(fill)) }
                        }
                    }
                }
            } else {
                ContentUnavailableView("找不到这笔委托", systemImage: "doc.text.magnifyingglass",
                                       description: Text("记录可能还在同步，稍后再看。"))
            }
        }
        .portSightBackdrop()
        .navigationTitle(history?.title ?? "委托记录")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - One record

struct IBKRActivityDetail: View {
    let item: IBKRActivity
    /// The order page this detail was pushed from (its perm_id), if any: then 「查看这笔委托的状态变化」 goes back to it.
    var openedFromOrder: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PortSightList {
            Section {
                LabeledContent("类型", value: kindTitle)
                if let symbol = item.symbol { LabeledContent("代码", value: symbol) }
                LabeledContent("时间", value: IBKRActivityText.dateTime(item.date))
                LabeledContent("来源", value: item.isRealtime ? "实时" : "IBKR 报表")
            }
            switch item.kind {
            case .fill:
                Section("成交") {
                    if let side = item.sideTitle { LabeledContent("方向", value: side) }
                    LabeledContent("数量", value: IBKRActivity.quantityText(item.quantity) + " 股")
                    LabeledContent("价格", value: IBKRActivity.money(item.price, item.currency))
                    if let value = item.signedValue { LabeledContent("金额", value: IBKRActivity.money(abs(value), item.currency)) }
                    if let commission = item.commission {
                        LabeledContent("佣金", value: IBKRActivity.money(abs(commission), item.commission_currency ?? item.currency))
                    }
                }
                orderLink
            case .order:
                Section("委托") {
                    LabeledContent("状态", value: item.statusTitle ?? "—")
                    if let side = item.sideTitle { LabeledContent("方向", value: side) }
                    if let type = item.order_type { LabeledContent("类型", value: IBKRActivity.orderTypeTitle(type)) }
                    if let limit = item.limit_price { LabeledContent("限价", value: IBKRActivity.money(limit, item.currency)) }
                    if let quantity = item.quantity { LabeledContent("数量", value: IBKRActivity.quantityText(quantity) + " 股") }
                    if let filled = item.filled { LabeledContent("已成交", value: IBKRActivity.quantityText(filled)) }
                    if let remaining = item.remaining { LabeledContent("剩余", value: IBKRActivity.quantityText(remaining)) }
                }
                orderLink
            case .position:
                Section("持仓变化") {
                    LabeledContent("之前", value: IBKRActivity.quantityText(item.old_quantity))
                    LabeledContent("之后", value: IBKRActivity.quantityText(item.new_quantity))
                }
            case .cash:
                Section("资金") {
                    LabeledContent("类别", value: item.cashTitle)
                    LabeledContent("金额") {
                        Text(IBKRActivity.money(item.amount, item.currency))
                            .foregroundStyle((item.amount ?? 0) > 0 ? Color.green : Color.primary)
                    }
                    if let description = item.description { Text(description).foregroundStyle(.secondary) }
                }
            case .other:
                if let description = item.description { Section { Text(description) } }
            }
        }
        .portSightBackdrop()
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The order this fill or status change belongs to, when it is known.
    @ViewBuilder private var orderLink: some View {
        if let perm = item.perm_id, IBKRActivityList.order(perm, in: IBKRActivityStore.shared.items) != nil {
            Section {
                if perm == openedFromOrder {
                    // Came from that order's page: back to it, not one more level down.
                    Button { dismiss() } label: {
                        Label("返回这笔委托的状态变化", systemImage: "chevron.backward")
                    }
                } else {
                    NavigationLink { IBKROrderHistoryView(permID: perm) } label: {
                        Label("查看这笔委托的状态变化", systemImage: "list.bullet.rectangle")
                    }
                }
            }
        }
    }

    private var kindTitle: String {
        switch item.kind {
        case .fill: "成交"
        case .order: "委托"
        case .position: "持仓变化"
        case .cash: "资金流水"
        case .other: "账户活动"
        }
    }
}

// MARK: - Cash totals

/// 入金 / 出金 / 分红 / 利息 / 费用 / 税, summed per currency, with net deposits.
struct IBKRCashSummarySection: View {
    let items: [IBKRActivity]

    var body: some View {
        let currencies = IBKRActivityList.cashTotalsByCurrency(items)
        ForEach(currencies, id: \.currency) { group in
            Section {
                ForEach(IBKRCashType.allCases.filter { group.totals[$0] != nil }) { type in
                    LabeledContent {
                        Text(IBKRActivity.money(group.totals[type], group.currency)).monospacedDigit()
                    } label: {
                        Label(type.title, systemImage: type.icon)
                    }
                }
                if group.totals[.deposit] != nil || group.totals[.withdrawal] != nil {
                    LabeledContent {
                        Text(IBKRActivity.money((group.totals[.deposit] ?? 0) + (group.totals[.withdrawal] ?? 0), group.currency))
                            .monospacedDigit().fontWeight(.semibold)
                    } label: {
                        Label("净入金", systemImage: "arrow.left.arrow.right")
                    }
                }
            } header: {
                Text(currencies.count > 1 ? "资金汇总 · " + group.currency : "资金汇总")
            } footer: {
                Text("入金和出金不计入投资收益。")
            }
        }
    }
}

// MARK: - 订单 page

/// The personal IBKR account's orders for the 订单 page: one line per order, by day, optionally for one symbol
/// and only open or only finished ones.
struct IBKROrderSections: View {
    enum Status: String, CaseIterable, Identifiable {
        case all = "全部", open = "进行中", done = "已结束"
        var id: String { rawValue }
    }

    let status: Status
    let symbol: String?
    let search: String

    var body: some View {
        let store = IBKRActivityStore.shared
        let entries = IBKRActivityList.timeline(store.items, filter: .trades, search: search).filter { entry in
            guard case .order(let history) = entry else { return false }
            if let symbol, history.symbol?.uppercased() != Self.ticker(symbol) { return false }
            switch status {
            case .all: return true
            case .open: return history.isOpen
            case .done: return !history.isOpen
            }
        }
        if entries.isEmpty {
            Section {
                if !search.isEmpty, !store.items.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else if store.phase.isLoading, store.items.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    ContentUnavailableView(status == .open ? "没有进行中的委托" : "还没有委托记录",
                                           systemImage: "list.bullet.rectangle",
                                           description: store.phase.placeholder()?.detail.map { Text($0) })
                }
            }
        }
        ForEach(IBKRActivityList.byDay(entries), id: \.day) { group in
            Section(IBKRActivityList.dayTitle(group.day)) {
                ForEach(group.entries) { entry in
                    NavigationLink { IBKRTimelineDestination(entry: entry) } label: { IBKRTimelineRow(entry: entry) }
                }
            }
        }
        if !entries.isEmpty, !store.reachedStart {
            HStack { Spacer(); ProgressView(); Spacer() }
                .listRowBackground(Color.clear)
                .task(id: store.items.count) { await store.loadOlder() }
        }
    }

    /// "US.AAPL" → "AAPL".
    static func ticker(_ symbol: String) -> String {
        (symbol.split(separator: ".").last.map(String.init) ?? symbol).uppercased()
    }
}

// MARK: - Text

enum IBKRActivityText {
    /// "14:05" in the phone's time zone.
    static func clock(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// "2026年11月10日 14:05".
    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.year().month().day().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            .locale(Locale(identifier: "zh_CN")))
    }

    /// "离线：显示 14:05 保存的记录" while the list is a saved copy.
    static func savedNote(_ store: IBKRActivityStore) -> String? {
        guard store.isSaved else { return nil }
        guard let readAt = store.readAt else { return "离线：显示保存的记录" }
        return "离线：显示 " + dateTime(readAt) + " 保存的记录"
    }

    static func statusIcon(_ order: IBKRActivity?) -> String {
        switch order?.status?.lowercased() {
        case "submitted": "paperplane"
        case "modified": "pencil.circle"
        case "partially_filled": "circle.lefthalf.filled"
        case "filled": "checkmark.circle.fill"
        case "cancelled", "canceled": "xmark.circle"
        case "rejected": "exclamationmark.triangle"
        case "inactive": "pause.circle"
        default: "list.bullet.rectangle"
        }
    }

    static func statusTint(_ order: IBKRActivity?) -> Color {
        switch order?.status?.lowercased() {
        case "filled": .green
        case "rejected": .red
        case "partially_filled", "submitted", "modified": .orange
        default: .secondary
        }
    }
}
