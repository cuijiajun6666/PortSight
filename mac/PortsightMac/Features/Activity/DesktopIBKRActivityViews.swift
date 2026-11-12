//
//  DesktopIBKRActivityViews.swift
//  PortsightMac
//
//  The personal IBKR account's activity once paired (IBKRActivityStore, GET /ibkr/activity), for 动态 and 订单:
//  the timeline rows by day (each order folded into one line), an order's status changes tied together by
//  perm_id, a record's details, and the cash totals. Times are shown in this Mac's time zone.
//

import SwiftUI
import PortSightKit

// MARK: - Timeline

/// The 动态 card's rows once paired: by day, newest first; clicking one selects it (the page shows its sheet).
struct DesktopIBKRTimeline: View {
    let entries: [IBKRTimelineEntry]
    @Binding var selection: DesktopIBKRSelection?

    var body: some View {
        let store = IBKRActivityStore.shared
        let days = IBKRActivityList.byDay(entries)
        // Lazy: the history can run to thousands of lines, and the older page is read only when its end scrolls
        // into view (a plain stack would build the last row at once and read every page in a row).
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(days, id: \.day) { group in
                Text(IBKRActivityList.dayTitle(group.day))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.top, group.day == days.first?.day ? 0 : 18).padding(.bottom, 4)
                ForEach(group.entries) { entry in
                    Button { selection = DesktopIBKRSelection(entry: entry) } label: { DesktopIBKRRow(entry: entry) }
                        .buttonStyle(.plain)
                    if entry.id != group.entries.last?.id { Divider().opacity(0.5) }
                }
            }
            if !entries.isEmpty {
                if !store.reachedStart {
                    HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                        .padding(.vertical, 16)
                        .task(id: store.items.count) { await store.loadOlder() }
                } else {
                    Text("IBKR 只提供 2026 年 5 月 14 日以后的报表，这里已是全部记录。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 16)
                }
            }
        }
    }
}

/// What the page's sheet shows.
struct DesktopIBKRSelection: Identifiable {
    let entry: IBKRTimelineEntry
    var id: String { entry.id }

    init(entry: IBKRTimelineEntry) { self.entry = entry }

    /// A row built from IBKRTimelineEntry.asDemoActivity (最近动态, 相关交易): its id ("order:<perm_id>" for an order,
    /// the record's own id otherwise) finds the entry again. Nil when it is no longer in the store.
    init?(activityID: String) {
        guard let entry = IBKRActivityList.timeline(IBKRActivityStore.shared.items).first(where: { $0.id == activityID })
        else { return nil }
        self.entry = entry
    }

    /// 「AAPL · 订单详情」 for an order, 「动态详情」 for a single record.
    var title: String {
        switch entry {
        case .order(let history): (history.symbol.map { $0 + " · " } ?? "") + "订单详情"
        case .record: "动态详情"
        }
    }
}

struct DesktopIBKRRow: View {
    let entry: IBKRTimelineEntry

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(tint)
                .frame(width: 46, height: 46).background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(entry.title).font(.system(size: 14, weight: .semibold))
                    if !isRealtime { DesktopPill(text: "报表", color: .secondary) }
                }
                Text(entry.detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                if let amount {
                    Text(IBKRActivity.money(amount, currency)).font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(amount > 0 ? DesktopTheme.green : .primary)
                }
                Text(DesktopIBKRText.clock(entry.date)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 20)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch entry {
        case .order(let history): DesktopIBKRText.statusIcon(history.latest)
        case .record(let item):
            switch item.kind {
            case .fill: item.isBuy ? "arrow.down.left" : "arrow.up.right"
            case .cash: IBKRCashType(item.type).icon
            case .position: "chart.bar.doc.horizontal"
            case .order: DesktopIBKRText.statusIcon(item)
            case .other: "circle"
            }
        }
    }

    private var tint: Color {
        switch entry {
        case .order(let history): DesktopIBKRText.statusTint(history.latest)
        case .record: DesktopTheme.blue
        }
    }

    private var amount: Double? {
        switch entry {
        case .order(let history): history.fills.isEmpty ? nil : history.fills.reduce(0) { $0 + ($1.signedValue ?? 0) }
        case .record(let item): item.kind == .fill ? item.signedValue : item.kind == .cash ? item.amount : nil
        }
    }

    private var currency: String? {
        switch entry {
        case .order(let history): history.fills.first?.currency ?? history.latest?.currency
        case .record(let item): item.currency
        }
    }

    private var isRealtime: Bool {
        switch entry {
        case .order(let history): history.steps.contains { $0.isRealtime }
        case .record(let item): item.isRealtime
        }
    }
}

// MARK: - Details (sheet content)

struct DesktopIBKREntryDetail: View {
    let entry: IBKRTimelineEntry

    var body: some View {
        switch entry {
        case .order(let history): DesktopIBKROrderDetail(permID: history.id)
        case .record(let item): DesktopIBKRRecordDetail(item: item)
        }
    }
}

/// Every status the order went through, oldest first, and its fills.
struct DesktopIBKROrderDetail: View {
    let permID: String

    var body: some View {
        let history = IBKRActivityList.order(permID, in: IBKRActivityStore.shared.items)
        Form {
            if let history {
                Section {
                    LabeledContent("代码", value: history.symbol ?? "—")
                    LabeledContent("方向", value: history.isBuy ? "买入" : "卖出")
                    if let type = history.latest?.order_type { LabeledContent("类型", value: IBKRActivity.orderTypeTitle(type)) }
                    // 股 / 张 (options) / 手 (futures), nothing for a currency (AUD.USD).
                    if let quantity = history.quantity { LabeledContent("委托数量", value: history.quantityWithUnit(abs(quantity))) }
                    if history.filledQuantity > 0 {
                        LabeledContent("已成交", value: history.quantityWithUnit(history.filledQuantity))
                    }
                    if let limit = history.steps.last(where: { $0.limit_price != nil })?.limit_price {
                        LabeledContent("限价", value: IBKRActivity.money(limit, history.latest?.currency))
                    }
                    if !history.fills.isEmpty, let average = history.averagePrice {
                        LabeledContent("成交均价", value: IBKRActivity.money(average, history.fills.first?.currency))
                    }
                    LabeledContent("状态") {
                        Text(history.latest?.statusTitle ?? "—").foregroundStyle(DesktopIBKRText.statusTint(history.latest))
                    }
                }
                Section("状态变化") {
                    ForEach(history.steps) { step in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: DesktopIBKRText.statusIcon(step))
                                .foregroundStyle(DesktopIBKRText.statusTint(step)).frame(width: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.statusTitle ?? "更新").fontWeight(.medium)
                                Text(step.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(DesktopIBKRText.dateTime(step.date)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !history.fills.isEmpty {
                    Section("成交") {
                        ForEach(history.fills) { fill in
                            LabeledContent {
                                Text(IBKRActivity.money(fill.signedValue.map { abs($0) }, fill.currency)).monospacedDigit()
                            } label: {
                                Text(fill.detail)
                                Text(DesktopIBKRText.dateTime(fill.date) + (fill.isRealtime ? "" : " · IBKR 报表"))
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("找不到这笔委托", systemImage: "doc.text.magnifyingglass",
                                       description: Text("记录可能还在同步，稍后再看。"))
            }
        }
        .formStyle(.grouped)
    }
}

struct DesktopIBKRRecordDetail: View {
    let item: IBKRActivity

    var body: some View {
        Form {
            Section {
                LabeledContent("事件", value: item.title)
                if let symbol = item.symbol { LabeledContent("代码", value: symbol) }
                LabeledContent("时间", value: DesktopIBKRText.dateTime(item.date))
                LabeledContent("来源", value: item.isRealtime ? "实时" : "IBKR 报表")
            }
            switch item.kind {
            case .fill:
                Section("成交") {
                    if let side = item.sideTitle { LabeledContent("方向", value: side) }
                    LabeledContent("数量", value: item.quantityWithUnit(item.quantity))
                    LabeledContent("价格", value: IBKRActivity.money(item.price, item.currency))
                    if let value = item.signedValue { LabeledContent("金额", value: IBKRActivity.money(abs(value), item.currency)) }
                    if let commission = item.commission {
                        LabeledContent("佣金", value: IBKRActivity.money(abs(commission), item.commission_currency ?? item.currency))
                    }
                }
            case .order:
                Section("委托") {
                    LabeledContent("状态", value: item.statusTitle ?? "—")
                    if let type = item.order_type { LabeledContent("类型", value: IBKRActivity.orderTypeTitle(type)) }
                    if let limit = item.limit_price { LabeledContent("限价", value: IBKRActivity.money(limit, item.currency)) }
                    if let quantity = item.quantity { LabeledContent("数量", value: item.quantityWithUnit(quantity)) }
                }
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
                            .foregroundStyle((item.amount ?? 0) > 0 ? DesktopTheme.green : .primary)
                    }
                    if let description = item.description { Text(description).foregroundStyle(.secondary) }
                }
            case .other:
                if let description = item.description { Section { Text(description) } }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Cash totals

/// 入金 / 出金 / 分红 / 利息 / 费用 / 税 per currency, and net deposits.
struct DesktopIBKRCashSummary: View {
    let items: [IBKRActivity]

    var body: some View {
        let currencies = IBKRActivityList.cashTotalsByCurrency(items)
        VStack(alignment: .leading, spacing: 14) {
            ForEach(currencies, id: \.currency) { group in
                HStack(spacing: 0) {
                    ForEach(IBKRCashType.allCases.filter { group.totals[$0] != nil }) { type in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(type.title + (currencies.count > 1 ? " · " + group.currency : ""), systemImage: type.icon)
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(IBKRActivity.money(group.totals[type], group.currency))
                                .font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if group.totals[.deposit] != nil || group.totals[.withdrawal] != nil {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("净入金", systemImage: "arrow.left.arrow.right").font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(IBKRActivity.money((group.totals[.deposit] ?? 0) + (group.totals[.withdrawal] ?? 0), group.currency))
                                .font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: - Text

enum DesktopIBKRText {
    static func clock(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.year().month().day().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            .locale(Locale(identifier: "zh_CN")))
    }

    /// An IBKR order's currency: its fills', or the order's own while nothing filled.
    static func currency(_ history: IBKROrderHistory) -> String? {
        history.fills.first?.currency ?? history.latest?.currency
    }

    /// An IBKR order's price: the average fill price, 「限价 …」 while nothing filled, or 「—」 (a market order not
    /// filled, an order cancelled before any fill). A limit is never shown as a fill price.
    static func orderPrice(_ history: IBKROrderHistory) -> String {
        if !history.fills.isEmpty, let average = history.averagePrice {
            return IBKRActivity.money(average, currency(history))
        }
        if let limit = history.steps.last(where: { $0.limit_price != nil })?.limit_price {
            return "限价 " + IBKRActivity.money(limit, currency(history))
        }
        return "—"
    }

    /// An IBKR order's size in its own unit: 「10 股」, 「2 张」 (options), 「1 手」 (futures), 「4.8906」 (a currency).
    static func orderQuantity(_ history: IBKROrderHistory) -> String {
        history.quantity.map { history.quantityWithUnit(abs($0)) } ?? "—"
    }

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
        case "filled": DesktopTheme.green
        case "rejected": .red
        case "partially_filled", "submitted", "modified": DesktopTheme.orange
        default: .secondary
        }
    }
}
