import SwiftUI
import SwiftData
import AppKit
import PortSightKit
private struct OrderLogoSnapshot {
    let image: NSImage?
    let byteCount: Int
    let featureColor: Color?
}

private struct OrderRenderSnapshot {
    let displayedOrders: [PortfolioOrder]
    let orderFilterSymbols: [String]
    let orderLogoSymbols: [String]
    let listAnimationKey: String
    let symbolFilterAnimationKey: String
    let sourceSignature: String

    static let empty = OrderRenderSnapshot(
        displayedOrders: [],
        orderFilterSymbols: [],
        orderLogoSymbols: [],
        listAnimationKey: "empty",
        symbolFilterAnimationKey: "empty",
        sourceSignature: ""
    )

    static func make(
        orders: [PortfolioOrder],
        selectedStatus: OrderStatusFilter,
        selectedOrderSymbol: String?,
        detailSymbol: String?
    ) -> OrderRenderSnapshot {
        let detailTicker = detailSymbol.map(Self.logoTicker)
        let statusScopedOrders = orders
            .filter { order in
                guard let detailTicker else { return true }
                return Self.logoTicker(order.symbol) == detailTicker
            }
            .filter { $0.status == selectedStatus.status }

        let displayedOrders = statusScopedOrders
            .filter { order in
                guard let selectedOrderSymbol else { return true }
                return Self.logoTicker(order.symbol) == selectedOrderSymbol
            }
            .sorted { $0.date > $1.date }

        let totalsBySymbol = statusScopedOrders.reduce(into: [String: Double]()) { result, order in
            result[Self.logoTicker(order.symbol), default: 0] += abs(order.price * order.quantity)
        }

        let orderFilterSymbols = totalsBySymbol.keys.sorted { lhs, rhs in
            let lhsTotal = totalsBySymbol[lhs] ?? 0
            let rhsTotal = totalsBySymbol[rhs] ?? 0

            if lhsTotal == rhsTotal {
                return lhs < rhs
            }

            return lhsTotal > rhsTotal
        }

        var logoSymbols = Set(orders.map { Self.logoTicker($0.symbol) })
        if let detailTicker {
            logoSymbols.insert(detailTicker)
        }
        for orderSymbol in orderFilterSymbols {
            logoSymbols.insert(orderSymbol)
        }

        let displayedOrderIDs = displayedOrders.map(\.id).joined(separator: ",")
        let filterSymbolKey = orderFilterSymbols.joined(separator: ",")
        let sourceSignature = [
            selectedStatus.rawValue,
            selectedOrderSymbol ?? "ALL",
            detailTicker ?? "ALL",
            orders.map { "\($0.id):\($0.symbol):\($0.status):\($0.price):\($0.quantity):\($0.date.timeIntervalSince1970)" }.joined(separator: "|")
        ].joined(separator: "#")

        return OrderRenderSnapshot(
            displayedOrders: displayedOrders,
            orderFilterSymbols: orderFilterSymbols,
            orderLogoSymbols: Array(logoSymbols).sorted(),
            listAnimationKey: [selectedStatus.rawValue, selectedOrderSymbol ?? "ALL", displayedOrderIDs].joined(separator: "|"),
            symbolFilterAnimationKey: [selectedStatus.rawValue, selectedOrderSymbol ?? "ALL", filterSymbolKey].joined(separator: "|"),
            sourceSignature: sourceSignature
        )
    }

    private nonisolated static func logoTicker(_ symbol: String) -> String {
        var text = symbol.uppercased()
        for prefix in ["US.", "HK.", "SH.", "SZ."] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        return text
    }
}

struct OrdersView: View {
    @State private var selectedStatus: OrderStatusFilter = .pending
    @State private var selectedOrderSymbol: String?
    @State private var lastSyncedOrderLogoKey = ""
    @State private var loadedOrderLogoKey = ""
    @State private var hasStartedOrderRefresh = false
    @State private var canSyncOrderLogos = false
    @State private var logoSnapshotsByTicker: [String: OrderLogoSnapshot] = [:]
    @State private var orderRenderSnapshot: OrderRenderSnapshot = .empty
    @StateObject private var dealsVM = DealsViewModel()
    @StateObject private var openOrdersVM = OpenOrdersViewModel()
    @Environment(\.modelContext) private var modelContext

    let orders: [PortfolioOrder]
    let symbol: String?

    init(orders: [PortfolioOrder] = [], symbol: String? = nil) {
        self.orders = orders
        self.symbol = symbol
    }

    private var allOrders: [PortfolioOrder] {
        orders + openOrdersVM.pendingOrders + dealsVM.completedOrders
    }

    /// Once paired: the IBKR orders' histories by perm_id (an IBKR order's PortfolioOrder.id), so their rows show the
    /// fill price, 「限价 …」 or 「—」 in the order's own currency and unit. Empty before pairing: rows unchanged.
    private var liveHistories: [String: IBKROrderHistory] {
        guard Portfolio.isLive else { return [:] }
        return Dictionary(IBKRActivityList.orders(IBKRActivityStore.shared.items).map { ($0.id, $0) },
                          uniquingKeysWith: { first, _ in first })
    }

    private var displayedOrders: [PortfolioOrder] {
        currentOrderRenderSnapshot.displayedOrders
    }

    private var orderFilterSymbols: [String] {
        currentOrderRenderSnapshot.orderFilterSymbols
    }

    private var orderLogoSymbols: [String] {
        currentOrderRenderSnapshot.orderLogoSymbols
    }

    private var listAnimationKey: String {
        currentOrderRenderSnapshot.listAnimationKey
    }

    private var symbolFilterAnimationKey: String {
        currentOrderRenderSnapshot.symbolFilterAnimationKey
    }

    private var currentOrderRenderSnapshot: OrderRenderSnapshot {
        if !orderRenderSnapshot.sourceSignature.isEmpty {
            return orderRenderSnapshot
        }

        return makeOrderRenderSnapshot()
    }

    var body: some View {
        ZStack {
            List {
                if symbol == nil {
                    Section {
                        Text("占位")
                            .foregroundStyle(.clear)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                Section {
                    if displayedOrders.isEmpty {
                        EmptyOrdersView(status: selectedStatus, symbol: symbol)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    } else {
                        let histories = liveHistories
                        ForEach(displayedOrders) { order in
                            OrderRow(
                                order: order,
                                history: histories[order.id]
                            )
                        }
                    }
                }
            }
            .listStyle(.inset)
            .refreshable {
                await refreshOrdersFromServer()
            }
            .animation(.default, value: listAnimationKey)
            .navigationTitle(symbol.map { "\(logoTicker(for: $0)) 订单" } ?? "订单")
            
            
            VStack(spacing: 0) {
                if symbol == nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            OrderSymbolFilterChip(
                                title: "全部",
                                isSelected: selectedOrderSymbol == nil,
                                tint: .primary,
                                logoSymbol: nil
                            ) {
                                withAnimation {
                                    selectedOrderSymbol = nil
                                    refreshOrderRenderSnapshot()
                                }
                            }

                            ForEach(orderFilterSymbols, id: \.self) { orderSymbol in
                                OrderSymbolFilterChip(
                                    title: orderSymbol,
                                    isSelected: selectedOrderSymbol == orderSymbol,
                                    tint: orderFilterColor(for: orderSymbol),
                                    logoSymbol: orderSymbol
                                ) {
                                    withAnimation(.interpolatingSpring) {
                                        selectedOrderSymbol = orderSymbol
                                        refreshOrderRenderSnapshot()
                                    }
                                }
                                .transition(
                                    .opacity.combined(with: .scale(scale: 0.92))
                                )
                            }
                        }
                        .padding()
                        .padding(.vertical)
                        .animation(.default, value: symbolFilterAnimationKey)
                    }
                }
                DesktopCapsulePicker(title: "订单状态", options: OrderStatusFilter.allCases, selection: Binding(
                    get: { selectedStatus },
                    set: { newValue in
                        withAnimation {
                            selectedStatus = newValue
                            resetSelectedSymbolIfNeeded(for: newValue)
                            refreshOrderRenderSnapshot()
                        }
                    }
                )) { $0.rawValue }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .padding(.horizontal)
                .offset(y: symbol == nil ? -45 : -5)
                
                Spacer()
            }
            
        }
        .task {
            if DemoPortfolioData.enabled { refreshOrderRenderSnapshot(); return }
            guard !hasStartedOrderRefresh else { return }
            hasStartedOrderRefresh = true

            await dealsVM.loadCacheIfNeeded()
            await openOrdersVM.loadCacheIfNeeded()
            refreshOrderRenderSnapshot()
            await loadOrderLogoSnapshotsIfNeeded()

            dealsVM.startBackgroundSync(initialDelay: 0.2)
            openOrdersVM.startBackgroundSync(initialDelay: 0.3)

            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            canSyncOrderLogos = true
            await syncOrderLogosIfNeeded()
        }
        .onDisappear {
            dealsVM.stopBackgroundSync()
            openOrdersVM.stopBackgroundSync()
        }
        .onReceive(dealsVM.$completedOrders) { _ in
            refreshOrderRenderSnapshot()
        }
        .onReceive(openOrdersVM.$pendingOrders) { _ in
            refreshOrderRenderSnapshot()
        }
        .onChange(of: orderRenderSnapshot.symbolFilterAnimationKey) { _, _ in
            withAnimation {
                resetSelectedSymbolIfNeeded(for: selectedStatus)
                refreshOrderRenderSnapshot()
            }
        }
        .onChange(of: orderRenderSnapshot.orderLogoSymbols.joined(separator: "|")) { _, _ in
            if DemoPortfolioData.enabled { return }
            Task {
                await loadOrderLogoSnapshotsIfNeeded()

                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                await syncOrderLogosIfNeeded()
            }
        }
    }

    private func makeOrderRenderSnapshot() -> OrderRenderSnapshot {
        OrderRenderSnapshot.make(
            orders: allOrders,
            selectedStatus: selectedStatus,
            selectedOrderSymbol: selectedOrderSymbol,
            detailSymbol: symbol
        )
    }

    private func refreshOrderRenderSnapshot() {
        let snapshot = makeOrderRenderSnapshot()
        guard snapshot.sourceSignature != orderRenderSnapshot.sourceSignature else { return }
        orderRenderSnapshot = snapshot
    }

    private func refreshOrdersFromServer() async {
        if DemoPortfolioData.enabled { refreshOrderRenderSnapshot(); return }
        dealsVM.stopBackgroundSync()
        openOrdersVM.stopBackgroundSync()

        async let refreshedDeals: Void = dealsVM.fetchDeals()
        async let refreshedOpenOrders: Void = openOrdersVM.fetchOpenOrders()
        _ = await (refreshedDeals, refreshedOpenOrders)

        refreshOrderRenderSnapshot()
    }

    /// A selected capsule is tinted with its stock's colour: from the real icon on this Mac (SymbolLogoStore), else
    /// blue — never the text colour.
    private func orderFilterColor(for symbol: String) -> Color {
        if let saved = logoSnapshotsByTicker[logoTicker(for: symbol)]?.featureColor { return saved }
        return DesktopOrderChipColors.color(for: logoTicker(for: symbol)) ?? .blue
    }

    private func logoTicker(for symbol: String) -> String {
        SymbolLogoStore.displayTicker(symbol)
    }

    private func resetSelectedSymbolIfNeeded(for status: OrderStatusFilter) {
        guard let selectedOrderSymbol else { return }

        let availableSymbols = Set(orderFilterSymbols)
        guard !availableSymbols.contains(selectedOrderSymbol) else { return }

        self.selectedOrderSymbol = nil
    }

    private func syncOrderLogosIfNeeded() async {
        guard canSyncOrderLogos else { return }

        let symbolKey = orderLogoSymbols.joined(separator: "|")
        guard !symbolKey.isEmpty, symbolKey != lastSyncedOrderLogoKey else { return }

        lastSyncedOrderLogoKey = symbolKey
        let records = orderLogoRecords(for: orderLogoSymbols)
        await syncStockLogoRecords(
            symbols: orderLogoSymbols,
            records: records,
            modelContext: modelContext
        )
        loadedOrderLogoKey = ""
        await loadOrderLogoSnapshotsIfNeeded()
    }

    private func loadOrderLogoSnapshotsIfNeeded() async {
        let symbolKey = orderLogoSymbols.joined(separator: "|")
        guard !symbolKey.isEmpty, symbolKey != loadedOrderLogoKey else { return }

        loadedOrderLogoKey = symbolKey
        let records = orderLogoRecords(for: orderLogoSymbols)
        let snapshots = records.reduce(into: [String: OrderLogoSnapshot]()) { result, record in
            guard orderLogoSymbols.contains(record.ticker) else { return }
            result[record.ticker] = OrderLogoSnapshot(
                image: NSImage(data: record.imageData),
                byteCount: record.imageData.count,
                featureColor: record.featureColor
            )
        }

        guard logoSnapshotSignature(logoSnapshotsByTicker) != logoSnapshotSignature(snapshots) else {
            return
        }

        logoSnapshotsByTicker = snapshots
    }

    private func orderLogoRecords(for symbols: [String]) -> [StockLogoRecord] {
        let tickers = Set(symbols.map { $0.uppercased() })
        guard !tickers.isEmpty else { return [] }

        do {
            let descriptor = FetchDescriptor<StockLogoRecord>()
            return try modelContext.fetch(descriptor)
                .filter { tickers.contains($0.ticker) }
        } catch {
            print("fetch order logos error:", error.localizedDescription)
            return []
        }
    }

    private func logoSnapshotSignature(_ snapshots: [String: OrderLogoSnapshot]) -> String {
        snapshots.keys.sorted().map { ticker in
            let snapshot = snapshots[ticker]
            let color = snapshot?.featureColor == nil ? "nil" : "color"
            return "\(ticker):\(snapshot?.byteCount ?? 0):\(color)"
        }.joined(separator: "|")
    }
}

private enum OrderStatusFilter: String, CaseIterable, Identifiable {
    case pending = "未完成"
    case completed = "已完成"

    var id: String { rawValue }

    var status: PortfolioOrder.Status {
        switch self {
        case .pending:
            return .pending
        case .completed:
            return .completed
        }
    }
}

private struct OrderSymbolFilterChip: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let isSelected: Bool
    let tint: Color
    /// The symbol whose real icon leads the chip (SymbolLogoStore); nil for 「全部」.
    let logoSymbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let logoSymbol {
                    DesktopSymbolLogo(symbol: logoSymbol, size: 19)
                }

                Text(title)
                    .font(.system(size: 23))
                    .fontWeight(.semibold)
            }
            .padding(5)
            .padding(.horizontal, 5)
            .foregroundStyle(isSelected ? selectedTextColor : .secondary)
            .glassEffect(
                isSelected
                ? .regular.tint(tint.opacity(0.9))
                : .regular,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .offset(y: -20)
    }

    private var selectedTextColor: Color {
        guard title == "全部" else { return .white }
        return colorScheme == .dark ? .black : .white
    }
}

private struct OrderRow: View {
    let order: PortfolioOrder
    /// Once paired, an IBKR order's status changes and fills (nil before pairing and for any other order).
    var history: IBKROrderHistory? = nil

    var body: some View {
        switch order.side {
        case .buy:
            BuyOrderRow(order: order, history: history)
        case .sell:
            SellOrderRow(order: order, history: history)
        }
    }
}

/// The price and size lines of a row. Without an IBKR history (before pairing): as always. An IBKR order: 「@ 」
/// and its average fill price, 「限价 …」 while nothing filled, or 「—」 (never the limit shown as a fill, never
/// 「@ $0.00」), in its own currency; its size in its own unit (股 / 张 / 手, none for a currency).
private enum OrderRowText {
    static func price(_ order: PortfolioOrder, _ history: IBKROrderHistory?) -> String {
        guard let history else { return String(format: "@ $%.2f", order.price) }
        let price = DesktopIBKRText.orderPrice(history)
        return history.fills.isEmpty ? price : "@ " + price
    }

    static func quantity(_ order: PortfolioOrder, _ history: IBKROrderHistory?) -> String {
        guard let history else { return String(format: "%.2f 股", order.quantity) }
        return DesktopIBKRText.orderQuantity(history)
    }
}

private struct BuyOrderRow: View {
    let order: PortfolioOrder
    let history: IBKROrderHistory?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                HStack(spacing: 3) {
                    OrderSymbolTitle(symbol: order.displaySymbol)

                    Text("买入")
                        .font(.headline)
                        .foregroundStyle(.green)
                }

                Spacer()

                Text(OrderRowText.price(order, history))
                    .font(.headline.weight(.semibold))
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: order.price)
            }

            HStack {
                Text(OrderRowText.quantity(order, history))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: order.quantity)
                
                if let stateText = displayStateText {
                    Text(stateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                orderTimeText
            }
        }
        .font(.subheadline)
    }

    private var displayStateText: String? {
        let fallback = order.status == .completed ? "已完成" : "未完成"
        let text = order.orderStateText ?? fallback

        if order.status == .pending, text == "未完成" {
            return nil
        }

        return text
    }

    private var orderTimeText: some View {
        Text(order.date, format: .dateTime.month().day().hour().minute())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
            .animation(.easeInOut, value: order.date)
    }
}

private struct SellOrderRow: View {
    let order: PortfolioOrder
    let history: IBKROrderHistory?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                HStack(spacing: 3) {
                    OrderSymbolTitle(symbol: order.displaySymbol)

                    Text("卖出")
                        .font(.headline)
                        .foregroundStyle(.red)
                }

                Spacer()


                Text(OrderRowText.price(order, history))
                    .font(.headline.weight(.semibold))
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: order.price)
            }

            HStack {
                Text(OrderRowText.quantity(order, history))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: order.quantity)

                Spacer()

                Text(order.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: order.date)
            }

//            HStack {
//                if let stateText = displayStateText {
//                    Text(stateText)
//                        .font(.caption)
//                        .foregroundStyle(.secondary)
//                }
//
//                Spacer()
//
//                
//            }
        }
        .font(.subheadline)
    }

    private var displayStateText: String? {
        let fallback = order.status == .completed ? "已完成" : "未完成"
        let text = order.orderStateText ?? fallback

        if order.status == .pending, text == "未完成" {
            return nil
        }

        return text
    }
}

private struct OrderSymbolTitle: View {
    let symbol: String

    var body: some View {
        HStack(spacing: 5) {
            // The real stock / ETF / coin icon (SymbolLogoStore), the letter while it loads.
            DesktopSymbolLogo(symbol: symbol, size: 19)

            Text(symbol)
                .font(.headline)
        }
    }
}

private struct EmptyOrdersView: View {
    let status: OrderStatusFilter
    let symbol: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: status == .pending ? "clock.badge" : "checkmark.circle")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(emptyTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 128)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptyTitle: String {
        let prefix = symbol.map { "\($0) " } ?? ""
        return "\(prefix)暂无\(status.rawValue)订单"
    }
}

#Preview {
    NavigationStack {
        OrdersView(
            orders: [
                PortfolioOrder(
                    symbol: "AAPL",
                    side: .buy,
                    status: .pending,
                    price: 196.20,
                    quantity: 3,
                    date: .now
                ),
                PortfolioOrder(
                    symbol: "NVDA",
                    side: .sell,
                    status: .completed,
                    price: 133.75,
                    quantity: 2,
                    date: .now.addingTimeInterval(-3600)
                )
            ]
        )
    }
}

/// Each icon's main colour, worked out once.
@MainActor
private enum DesktopOrderChipColors {
    private static var cache: [String: Color?] = [:]

    static func color(for ticker: String) -> Color? {
        let crypto = SymbolLogoStore.isCrypto(ticker)
        guard let data = SymbolLogoStore.shared.image(ticker, crypto: crypto) else { return nil }
        if let known = cache[ticker] { return known }
        let color = extractLogoFeatureColor(from: data)?.color
        cache[ticker] = color
        return color
    }
}
