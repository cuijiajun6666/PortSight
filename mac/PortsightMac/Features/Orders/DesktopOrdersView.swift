
import SwiftUI
import PortSightKit

/// 订单. Before pairing: the built-in orders (unchanged). Once paired: the personal IBKR account's orders, one row per
/// order (perm_id) with its latest status, a click showing every status change and fill; with the built-in quant
/// order (and the built-in personal one while IBKR has none), which open the sheet they always did
/// (Portfolio.orders). The activity heartbeat runs while this page is on screen and the app is in front.
struct DesktopOrdersView: View {
    @EnvironmentObject private var demo: PortfolioDemo
    /// Pairing or unpairing turns the page live or back (demo.isLive reads this store).
    @ObservedObject private var server = ServerStore.shared
    @Environment(\.desktopAppActive) private var appActive
    @State private var filter = "全部"
    @State private var symbol = ""
    @State private var selection: PortfolioOrder?
    @State private var showOriginal = false
    private func orders(_ all: [PortfolioOrder], _ histories: [String: IBKROrderHistory]) -> [PortfolioOrder] {
        all.filter {
            (filter == "全部" || (filter == "已成交" ? $0.status == .completed && traded($0, histories) : $0.status == .pending)) &&
            (symbol.isEmpty || $0.symbol.localizedCaseInsensitiveContains(symbol))
        }.sorted { $0.date > $1.date }
    }
    /// Once paired: each listed IBKR order's history (status steps and fills), by perm_id (PortfolioOrder.id). A
    /// built-in order has none.
    private var histories: [String: IBKROrderHistory] {
        guard demo.isLive, demo.scope != .quant else { return [:] }
        return Dictionary(IBKRActivityList.orders(IBKRActivityStore.shared.items).map { ($0.id, $0) },
                          uniquingKeysWith: { first, _ in first })
    }
    /// The order traded: a built-in completed order always; an IBKR order with shares filled (an order that ended
    /// without a fill — cancelled, rejected — is not a trade).
    private func traded(_ order: PortfolioOrder, _ histories: [String: IBKROrderHistory]) -> Bool {
        guard let history = histories[order.id] else { return order.status == .completed }
        return history.filledQuantity > 0 || history.latest?.status?.lowercased() == "filled"
    }
    /// Orders that traded (the 成交笔数): exactly the rows 「已成交」 lists, so the card and the filter agree. An order
    /// still open after part of it filled is listed under 「待成交」 and is not counted until it ends.
    private func filled(_ all: [PortfolioOrder], _ histories: [String: IBKROrderHistory]) -> [PortfolioOrder] {
        all.filter { $0.status == .completed && traded($0, histories) }
    }
    /// 成交金额 of every counted order: a built-in one's price × quantity (US dollars), an IBKR one's fills (shares ×
    /// fill price). Fills in more than one currency are never added together: the US dollar ones are shown (or, with
    /// none in dollars, the currency with the most fills) and the card says which.
    private func filledValue(_ all: [PortfolioOrder], _ histories: [String: IBKROrderHistory]) -> (text: String, detail: String) {
        var byCurrency: [String: (value: Double, fills: Int)] = [:]
        for order in filled(all, histories) {
            if let history = histories[order.id] {
                for fill in history.fills {
                    let code = (fill.currency ?? "USD").uppercased()
                    byCurrency[code, default: (0, 0)].value += abs(fill.signedValue ?? 0)
                    byCurrency[code, default: (0, 0)].fills += 1
                }
            } else {
                byCurrency["USD", default: (0, 0)].value += order.price * order.quantity
                byCurrency["USD", default: (0, 0)].fills += 1
            }
        }
        guard byCurrency.count > 1 else {
            let currency = byCurrency.keys.first ?? "USD"
            let value = byCurrency[currency]?.value ?? 0
            return (currency == "USD" ? DesktopTheme.money(value) : IBKRActivity.money(value, currency), "成交价格 × 成交数量")
        }
        let currency = byCurrency["USD"] != nil ? "USD"
            : byCurrency.max { ($0.value.fills, $1.key) < ($1.value.fills, $0.key) }?.key ?? "USD"
        let value = byCurrency[currency]?.value ?? 0
        return (currency == "USD" ? DesktopTheme.money(value) : IBKRActivity.money(value, currency),
                "仅计" + currencyName(currency) + "成交")
    }
    /// 「美元」, 「港币」…, or the code itself (「 EUR 」, spaced inside 「仅计 EUR 成交」).
    private func currencyName(_ code: String) -> String {
        switch code {
        case "USD": "美元"
        case "HKD": "港币"
        case "CNH", "CNY": "人民币"
        case "AUD": "澳元"
        default: " " + code + " "
        }
    }
    /// The price, or 「—」 for an order without one (an IBKR order not filled yet).
    private func price(_ order: PortfolioOrder) -> String { order.price == 0 ? "—" : DesktopTheme.money(order.price) }
    private func amount(_ order: PortfolioOrder) -> String {
        order.price == 0 ? "—" : DesktopTheme.money(order.price * order.quantity)
    }
    var body: some View {
        // Read once per update: once paired each of these goes through the whole activity store.
        let all = demo.orders
        let histories = self.histories
        DesktopPageScrollView {
            VStack(spacing: 20) {
                let value = filledValue(all, histories)
                HStack(spacing: 16) {
                    DesktopMetricCard(title: "成交笔数", value: "\(filled(all, histories).count)", detail: "当前资产范围的成交", icon: "checkmark.circle", tint: DesktopTheme.green)
                    DesktopMetricCard(title: "成交金额", value: value.text, detail: value.detail, icon: "banknote")
                    DesktopMetricCard(title: "待成交订单", value: "\(all.filter { $0.status == .pending }.count)", detail: "此工作台仅展示订单", icon: "clock", tint: DesktopTheme.orange)
                }
                DesktopCard {
                    VStack(spacing: 25) {
                        HStack {
                            DesktopSectionTitle(title: "交易记录", subtitle: "成交与待成交订单，一处查看")
                            Spacer()
                            TextField("搜索代码", text: $symbol).textFieldStyle(.roundedBorder).frame(width: 160)
                            DesktopCapsulePicker(title: "状态", options: ["全部", "已成交", "待成交"], selection: $filter) { $0 }.labelsHidden()
                        }
                        let rows = orders(all, histories)
                        if rows.isEmpty {
                            ContentUnavailableView("暂无订单", systemImage: "tray", description: Text("当前范围和筛选条件下没有订单。"))
                                .frame(height: 280)
                        } else {
                            ForEach(rows) { order in
                                Button { selection = order } label: {
                                    if let history = histories[order.id] {
                                        liveRow(order, history)
                                    } else {
                                        sampleRow(order)
                                    }
                                }.buttonStyle(.plain)
                                Divider().opacity(0.5)
                            }
                        }
                        HStack {
                            Spacer()
                            Button("查看订单筛选详情") { showOriginal = true }.buttonStyle(.glass).foregroundStyle(.primary).font(.system(size: 11))
                        }
                    }
                }
                if !histories.isEmpty, let saved = DesktopIBKRText.savedNote(IBKRActivityStore.shared) {
                    Text(saved).font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.scrollIndicators(.hidden)
        .closesForPush($selection)
        .sheet(item: $selection) { order in
            DesktopSheetContainer(title: order.displaySymbol + " · 订单详情") {
                if isIBKR(order) {
                    // Every status change (submitted → partially filled → filled / cancelled) and each fill.
                    DesktopIBKROrderDetail(permID: order.id)
                } else {
                    Form {
                        LabeledContent("资产代码", value: order.symbol)
                        LabeledContent("方向", value: order.side.rawValue)
                        LabeledContent("成交价格", value: price(order))
                        LabeledContent("数量", value: order.quantity.formatted())
                        LabeledContent("成交金额", value: amount(order))
                        LabeledContent("状态", value: order.orderStateText ?? "已成交")
                        LabeledContent("订单标识", value: order.id)
                    }.formStyle(.grouped)
                }
            }
        }
        .closesForPush($showOriginal)
        .sheet(isPresented: $showOriginal) {
            DesktopSheetContainer(title: "订单筛选") { OrdersView(orders: all) }
        }
        // Only while this page is on screen, the app is in front and a relay is paired: read now, then the
        // activity heartbeat every 10 s (only what is new). The quant account's order is built in.
        .task(id: [appActive, demo.isLive, demo.scope != .quant]) {
            guard appActive, demo.isLive, demo.scope != .quant else { return }
            await IBKRActivityStore.shared.runPolling()
        }
    }

    /// A real IBKR order (paired, the personal account's), not one of the built-in ones.
    private func isIBKR(_ order: PortfolioOrder) -> Bool {
        demo.isLive && IBKRActivityList.order(order.id, in: IBKRActivityStore.shared.items) != nil
    }

    // MARK: Rows

    private func sampleRow(_ order: PortfolioOrder) -> some View {
        HStack(spacing: 20) {
            DesktopSymbol(symbol: order.displaySymbol, size: 44)
            VStack(alignment: .leading, spacing: 7) {
                Text(order.displaySymbol).font(.system(size: 15, weight: .semibold))
                Text(order.date, format: .dateTime.month().day().hour().minute()).font(.system(size: 11)).foregroundStyle(.secondary)
            }.frame(width: 130, alignment: .leading)
            DesktopPill(text: order.side.rawValue, color: order.side == .buy ? DesktopTheme.green : .orange)
            Spacer()
            VStack(alignment: .trailing, spacing: 7) {
                Text("\(order.quantity.formatted()) 股 × " + price(order)).font(.system(size: 12))
                Text(order.orderStateText ?? "已成交").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text(amount(order)).font(.system(size: 18, weight: .semibold, design: .rounded)).frame(width: 140, alignment: .trailing)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }.padding(.vertical, 20).contentShape(Rectangle())
    }

    /// An IBKR order: shares × average fill price (or its limit while nothing filled), the latest status, and the
    /// value of what filled (「—」 when nothing did, never the limit × shares).
    private func liveRow(_ order: PortfolioOrder, _ history: IBKROrderHistory) -> some View {
        let currency = DesktopIBKRText.currency(history)
        let filledShares = history.filledQuantity
        // 「10 股 × $225.50」, 「2 张 · 限价 $3.10」, 「4.8906 × A$…」 (a currency has no unit), or just the size.
        let price = DesktopIBKRText.orderPrice(history)
        let figures = DesktopIBKRText.orderQuantity(history)
            + (price == "—" ? "" : (history.fills.isEmpty ? " · " : " × ") + price)
        // 「部分成交 3/10」, or 「已撤单 3/10」 for an order cancelled after part of it filled.
        var status = history.latest?.statusTitle ?? "—"
        if let quantity = history.quantity, filledShares > 0, filledShares < abs(quantity) {
            status += " " + IBKRActivity.quantityText(filledShares) + "/" + IBKRActivity.quantityText(abs(quantity))
        }
        let value: String = history.fills.isEmpty
            ? "—" : IBKRActivity.money(history.fills.reduce(0) { $0 + abs($1.signedValue ?? 0) }, currency)
        return HStack(spacing: 20) {
            DesktopSymbol(symbol: order.displaySymbol,
                          crypto: history.unitSource?.sec_type?.uppercased() == "CRYPTO" || SymbolLogoStore.isCrypto(order.displaySymbol),
                          size: 44)
            VStack(alignment: .leading, spacing: 7) {
                Text(order.displaySymbol).font(.system(size: 15, weight: .semibold))
                Text(order.date, format: .dateTime.month().day().hour().minute()).font(.system(size: 11)).foregroundStyle(.secondary)
            }.frame(width: 130, alignment: .leading)
            DesktopPill(text: order.side.rawValue, color: order.side == .buy ? DesktopTheme.green : .orange)
            Spacer()
            VStack(alignment: .trailing, spacing: 7) {
                Text(figures).font(.system(size: 12))
                Text(status).font(.system(size: 10)).foregroundStyle(DesktopIBKRText.statusTint(history.latest))
            }
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).frame(width: 140, alignment: .trailing)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }.padding(.vertical, 20).contentShape(Rectangle())
    }
}
