//
//  OrdersView.swift
//  PortSight
//
//  Created by Codex on 22/5/2026.
//

import SwiftUI
import SwiftData
import Combine

struct PortfolioOrder: Identifiable {
    enum Status {
        case pending
        case completed
    }

    enum Side: String {
        case buy = "买入"
        case sell = "卖出"
    }

    let id: String
    let symbol: String
    let side: Side
    let status: Status
    let price: Double
    let quantity: Double
    let date: Date
    let orderStateText: String?
    var displaySymbol: String {
        symbol.split(separator: ".").last.map(String.init)?.uppercased() ?? symbol.uppercased()
    }

    init(
        id: String = UUID().uuidString,
        symbol: String,
        side: Side,
        status: Status,
        price: Double,
        quantity: Double,
        date: Date,
        orderStateText: String? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.side = side
        self.status = status
        self.price = price
        self.quantity = quantity
        self.date = date
        self.orderStateText = orderStateText
    }
}

struct DealsResponse: Codable {
    let ok: Bool
    let updatedAt: String?
    let count: Int?
    let deals: [DealRecord]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case updatedAt = "updated_at"
        case count
        case deals
        case error
    }
}

struct DealRecord: Codable, Identifiable {
    var id: String { dealId }

    let code: String
    let stockName: String?
    let dealId: String
    let orderId: String?
    let qty: Double
    let price: Double
    let trdSide: String
    let createTime: String
    let status: String?

    enum CodingKeys: String, CodingKey {
        case code
        case stockName = "stock_name"
        case dealId = "deal_id"
        case orderId = "order_id"
        case qty
        case price
        case trdSide = "trd_side"
        case createTime = "create_time"
        case status
    }

    var asPortfolioOrder: PortfolioOrder {
        PortfolioOrder(
            id: dealId,
            symbol: code,
            side: trdSide.uppercased() == "SELL" ? .sell : .buy,
            status: .completed,
            price: price,
            quantity: qty,
            date: Self.parseDate(createTime) ?? .distantPast,
            orderStateText: status
        )
    }

    static func parseDate(_ value: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        let isoNoFractionFormatter = ISO8601DateFormatter()
        isoNoFractionFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoNoFractionFormatter.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")

        for format in ["yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }
}

struct OpenOrdersResponse: Codable {
    let ok: Bool
    let cached: Bool?
    let cacheAgeSeconds: Double?
    let updatedAt: String?
    let source: String?
    let count: Int?
    let orders: [OpenOrderRecord]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case cached
        case cacheAgeSeconds = "cache_age_seconds"
        case updatedAt = "updated_at"
        case source
        case count
        case orders
        case error
    }
}

struct OpenOrderRecord: Codable, Identifiable {
    var id: String { orderId }

    let code: String
    let stockName: String?
    let orderMarket: String?
    let trdSide: String
    let orderType: String?
    let orderStatus: String
    let orderId: String
    let qty: Double
    let price: Double
    let createTime: String
    let updatedTime: String?
    let dealtQty: Double?
    let dealtAvgPrice: Double?
    let lastErrMsg: String?
    let remark: String?
    let timeInForce: String?
    let fillOutsideRth: Bool?
    let session: String?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case code
        case stockName = "stock_name"
        case orderMarket = "order_market"
        case trdSide = "trd_side"
        case orderType = "order_type"
        case orderStatus = "order_status"
        case orderId = "order_id"
        case qty
        case price
        case createTime = "create_time"
        case updatedTime = "updated_time"
        case dealtQty = "dealt_qty"
        case dealtAvgPrice = "dealt_avg_price"
        case lastErrMsg = "last_err_msg"
        case remark
        case timeInForce = "time_in_force"
        case fillOutsideRth = "fill_outside_rth"
        case session
        case currency
    }

    var asPortfolioOrder: PortfolioOrder {
        PortfolioOrder(
            id: orderId,
            symbol: code,
            side: trdSide.uppercased() == "SELL" ? .sell : .buy,
            status: .pending,
            price: price,
            quantity: qty,
            date: DealRecord.parseDate(createTime) ?? .distantPast,
            orderStateText: orderStatus
        )
    }
}

private struct OrderLogoSnapshot {
    let image: UIImage?
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
        symbol.split(separator: ".").last.map(String.init)?.uppercased() ?? symbol.uppercased()
    }
}

@MainActor
final class DealsViewModel: ObservableObject {
    @Published private(set) var deals: [DealRecord] = []
    @Published private(set) var completedOrders: [PortfolioOrder] = []
    @Published private(set) var updatedAt: String?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let cacheKey = "deals_cache_v1"
    private let lastRefreshKey = "deals_last_refresh_at_v1"
    private var refreshTask: Task<Void, Never>?
    private var hasLoadedCache = false

    private static var memoryDeals: [DealRecord] = []
    private static var memoryCompletedOrders: [PortfolioOrder] = []
    private static var memoryUpdatedAt: String?
    private static var memorySignature = ""

    init() {
        loadMemoryCache()
    }

    func loadCache() {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true

        guard let cached = CacheManager.load(DealsResponse.self, key: cacheKey),
              cached.ok else {
            return
        }

        apply(cached, marksServerRefresh: false)
    }

    func loadCacheIfNeeded() async {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true

        guard let cached = await CacheManager.loadAsync(DealsResponse.self, key: cacheKey),
              cached.ok else {
            return
        }

        apply(cached, marksServerRefresh: false)
    }

    static func prewarmCacheIfNeeded() async {
        guard memoryDeals.isEmpty else { return }
        guard let cached = await CacheManager.loadAsync(DealsResponse.self, key: "deals_cache_v1"),
              cached.ok else {
            return
        }

        let snapshot = makeSnapshot(from: cached)
        memoryDeals = snapshot.deals
        memoryCompletedOrders = snapshot.orders
        memoryUpdatedAt = snapshot.updatedAt
        memorySignature = snapshot.signature
    }

    func fetchDeals() async {
        guard let url = BackendConfig.url(path: "deals") else {
            errorMessage = "URL 错误"
            return
        }

        isLoading = deals.isEmpty
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try await CacheManager.decode(DealsResponse.self, from: data)

            guard result.ok else {
                errorMessage = result.error ?? "历史成交接口返回失败"
                return
            }

            apply(result, marksServerRefresh: true)
            await CacheManager.saveAsync(result, key: cacheKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startBackgroundSync(initialDelay: Double = 0, minimumRefreshInterval: TimeInterval = 60) {
        guard refreshTask == nil else { return }
        guard shouldRefresh(minimumInterval: minimumRefreshInterval) else { return }

        refreshTask = Task {
            if initialDelay > 0 {
                try? await Task.sleep(for: .seconds(initialDelay))
            }

            guard !Task.isCancelled else { return }
            await fetchDeals()
            refreshTask = nil
        }
    }

    func stopBackgroundSync() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func apply(_ response: DealsResponse, marksServerRefresh: Bool) {
        let snapshot = Self.makeSnapshot(from: response)

        guard Self.memorySignature != snapshot.signature else {
            updatedAt = response.updatedAt
            errorMessage = nil
            if marksServerRefresh {
                UserDefaults.standard.set(Date(), forKey: lastRefreshKey)
            }
            return
        }

        deals = snapshot.deals
        completedOrders = snapshot.orders
        updatedAt = response.updatedAt
        errorMessage = nil
        Self.memoryDeals = snapshot.deals
        Self.memoryCompletedOrders = snapshot.orders
        Self.memoryUpdatedAt = snapshot.updatedAt
        Self.memorySignature = snapshot.signature
        if marksServerRefresh {
            UserDefaults.standard.set(Date(), forKey: lastRefreshKey)
        }
    }

    private func loadMemoryCache() {
        guard !Self.memoryDeals.isEmpty else { return }
        deals = Self.memoryDeals
        completedOrders = Self.memoryCompletedOrders
        updatedAt = Self.memoryUpdatedAt
        hasLoadedCache = true
    }

    private static func makeSnapshot(from response: DealsResponse) -> (deals: [DealRecord], orders: [PortfolioOrder], updatedAt: String?, signature: String) {
        let sortedDeals = response.deals.sorted {
            (DealRecord.parseDate($0.createTime) ?? .distantPast) >
            (DealRecord.parseDate($1.createTime) ?? .distantPast)
        }

        return (
            sortedDeals,
            sortedDeals.map(\.asPortfolioOrder),
            response.updatedAt,
            dealsSignature(sortedDeals)
        )
    }

    private static func dealsSignature(_ deals: [DealRecord]) -> String {
        deals.map {
            "\($0.dealId):\($0.code):\($0.qty):\($0.price):\($0.trdSide):\($0.createTime)"
        }.joined(separator: "|")
    }

    private func shouldRefresh(minimumInterval: TimeInterval) -> Bool {
        guard let lastRefresh = UserDefaults.standard.object(forKey: lastRefreshKey) as? Date else {
            return true
        }

        return Date().timeIntervalSince(lastRefresh) >= minimumInterval
    }
}

@MainActor
final class OpenOrdersViewModel: ObservableObject {
    @Published private(set) var orders: [OpenOrderRecord] = []
    @Published private(set) var pendingOrders: [PortfolioOrder] = []
    @Published private(set) var updatedAt: String?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let cacheKey = "open_orders_cache_v1"
    private let lastRefreshKey = "open_orders_last_refresh_at_v1"
    private var refreshTask: Task<Void, Never>?
    private var hasLoadedCache = false

    private static var memoryOrders: [OpenOrderRecord] = []
    private static var memoryPendingOrders: [PortfolioOrder] = []
    private static var memoryUpdatedAt: String?
    private static var memorySignature = ""

    init() {
        loadMemoryCache()
    }

    func loadCache() {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true

        guard let cached = CacheManager.load(OpenOrdersResponse.self, key: cacheKey),
              cached.ok else {
            return
        }

        apply(cached, marksServerRefresh: false)
    }

    static func prewarmCacheIfNeeded() async {
        guard memoryOrders.isEmpty else { return }
        guard let cached = await CacheManager.loadAsync(OpenOrdersResponse.self, key: "open_orders_cache_v1"),
              cached.ok else {
            return
        }

        let snapshot = makeSnapshot(from: cached)
        memoryOrders = snapshot.orders
        memoryPendingOrders = snapshot.pendingOrders
        memoryUpdatedAt = snapshot.updatedAt
        memorySignature = snapshot.signature
    }

    func loadCacheIfNeeded() async {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true

        guard let cached = await CacheManager.loadAsync(OpenOrdersResponse.self, key: cacheKey),
              cached.ok else {
            return
        }

        apply(cached, marksServerRefresh: false)
    }

    func fetchOpenOrders() async {
        guard let url = BackendConfig.url(path: "orders/open") else {
            errorMessage = "URL 错误"
            return
        }

        isLoading = orders.isEmpty
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try await CacheManager.decode(OpenOrdersResponse.self, from: data)

            guard result.ok else {
                errorMessage = result.error ?? "未完成订单接口返回失败"
                return
            }

            apply(result, marksServerRefresh: true)
            await CacheManager.saveAsync(result, key: cacheKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startBackgroundSync(initialDelay: Double = 0, minimumRefreshInterval: TimeInterval = 60) {
        guard refreshTask == nil else { return }
        guard shouldRefresh(minimumInterval: minimumRefreshInterval) else { return }

        refreshTask = Task {
            if initialDelay > 0 {
                try? await Task.sleep(for: .seconds(initialDelay))
            }

            guard !Task.isCancelled else { return }
            await fetchOpenOrders()
            refreshTask = nil
        }
    }

    func stopBackgroundSync() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func apply(_ response: OpenOrdersResponse, marksServerRefresh: Bool) {
        let snapshot = Self.makeSnapshot(from: response)

        guard Self.memorySignature != snapshot.signature else {
            updatedAt = response.updatedAt
            errorMessage = nil
            if marksServerRefresh {
                UserDefaults.standard.set(Date(), forKey: lastRefreshKey)
            }
            return
        }

        orders = snapshot.orders
        pendingOrders = snapshot.pendingOrders
        updatedAt = response.updatedAt
        errorMessage = nil
        Self.memoryOrders = snapshot.orders
        Self.memoryPendingOrders = snapshot.pendingOrders
        Self.memoryUpdatedAt = snapshot.updatedAt
        Self.memorySignature = snapshot.signature
        if marksServerRefresh {
            UserDefaults.standard.set(Date(), forKey: lastRefreshKey)
        }
    }

    private func loadMemoryCache() {
        guard !Self.memoryOrders.isEmpty else { return }
        orders = Self.memoryOrders
        pendingOrders = Self.memoryPendingOrders
        updatedAt = Self.memoryUpdatedAt
        hasLoadedCache = true
    }

    private static func makeSnapshot(from response: OpenOrdersResponse) -> (orders: [OpenOrderRecord], pendingOrders: [PortfolioOrder], updatedAt: String?, signature: String) {
        let sortedOrders = response.orders.sorted {
            (DealRecord.parseDate($0.createTime) ?? .distantPast) >
            (DealRecord.parseDate($1.createTime) ?? .distantPast)
        }

        return (
            sortedOrders,
            sortedOrders.map(\.asPortfolioOrder),
            response.updatedAt,
            ordersSignature(sortedOrders)
        )
    }

    private static func ordersSignature(_ orders: [OpenOrderRecord]) -> String {
        orders.map {
            "\($0.orderId):\($0.code):\($0.qty):\($0.price):\($0.trdSide):\($0.orderStatus):\($0.updatedTime ?? "")"
        }.joined(separator: "|")
    }

    private func shouldRefresh(minimumInterval: TimeInterval) -> Bool {
        guard let lastRefresh = UserDefaults.standard.object(forKey: lastRefreshKey) as? Date else {
            return true
        }

        return Date().timeIntervalSince(lastRefresh) >= minimumInterval
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
                        ForEach(displayedOrders) { order in
                            OrderRow(
                                order: order,
                                logoImage: orderFilterLogoImage(for: order.symbol)
                            )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await refreshOrdersFromServer()
            }
            .animation(.default, value: listAnimationKey)
            .navigationTitle(symbol.map { "\(logoTicker(for: $0)) 订单" } ?? "订单")
            .navigationBarTitleDisplayMode(.inline)
            
            VStack(spacing: 0) {
                if symbol == nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            OrderSymbolFilterChip(
                                title: "全部",
                                isSelected: selectedOrderSymbol == nil,
                                tint: .primary,
                                logoImage: nil
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
                                    logoImage: orderFilterLogoImage(for: orderSymbol)
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
                Picker("订单状态", selection: Binding(
                    get: { selectedStatus },
                    set: { newValue in
                        withAnimation {
                            selectedStatus = newValue
                            resetSelectedSymbolIfNeeded(for: newValue)
                            refreshOrderRenderSnapshot()
                        }
                    }
                )) {
                    ForEach(OrderStatusFilter.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .padding(.horizontal)
                .offset(y: symbol == nil ? -45 : -5)
                
                Spacer()
            }
            
        }
        .task {
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
        dealsVM.stopBackgroundSync()
        openOrdersVM.stopBackgroundSync()

        async let refreshedDeals: Void = dealsVM.fetchDeals()
        async let refreshedOpenOrders: Void = openOrdersVM.fetchOpenOrders()
        _ = await (refreshedDeals, refreshedOpenOrders)

        refreshOrderRenderSnapshot()
    }

    private func orderFilterColor(for symbol: String) -> Color {
        logoSnapshotsByTicker[logoTicker(for: symbol)]?.featureColor ?? .primary
    }

    private func orderFilterLogoImage(for symbol: String) -> UIImage? {
        logoSnapshotsByTicker[logoTicker(for: symbol)]?.image
    }

    private func logoTicker(for symbol: String) -> String {
        symbol.split(separator: ".").last.map(String.init)?.uppercased() ?? symbol.uppercased()
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
                image: UIImage(data: record.imageData),
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
    let logoImage: UIImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let logoImage {
                    Image(uiImage: logoImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 19, height: 19)
                        .clipShape(Circle())
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
    let logoImage: UIImage?

    var body: some View {
        switch order.side {
        case .buy:
            BuyOrderRow(order: order, logoImage: logoImage)
        case .sell:
            SellOrderRow(order: order, logoImage: logoImage)
        }
    }
}

private struct BuyOrderRow: View {
    let order: PortfolioOrder
    let logoImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                HStack(spacing: 3) {
                    OrderSymbolTitle(symbol: order.displaySymbol, logoImage: logoImage)

                    Text("买入")
                        .font(.headline)
                        .foregroundStyle(.green)
                }

                Spacer()

                Text("@ $\(order.price, specifier: "%.2f")")
                    .font(.headline.weight(.semibold))
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: order.price)
            }

            HStack {
                Text("\(order.quantity, specifier: "%.2f") 股")
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
    let logoImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                HStack(spacing: 3) {
                    OrderSymbolTitle(symbol: order.displaySymbol, logoImage: logoImage)

                    Text("卖出")
                        .font(.headline)
                        .foregroundStyle(.red)
                }

                Spacer()


                Text("@ $\(order.price, specifier: "%.2f")")
                    .font(.headline.weight(.semibold))
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: order.price)
            }

            HStack {
                Text("\(order.quantity, specifier: "%.2f") 股")
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
    let logoImage: UIImage?

    var body: some View {
        HStack(spacing: 5) {
            if let logoImage {
                Image(uiImage: logoImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 19, height: 19)
                    .clipShape(Circle())
            }

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
