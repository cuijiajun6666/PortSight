import Foundation
import Combine
@MainActor
public final class OpenOrdersViewModel: ObservableObject {
    @Published public private(set) var orders: [OpenOrderRecord] = []
    @Published public private(set) var pendingOrders: [PortfolioOrder] = []
    @Published public private(set) var updatedAt: String?
    @Published public private(set) var isLoading = false
    @Published public var errorMessage: String?

    private let cacheKey = "open_orders_cache_v1"
    private let lastRefreshKey = "open_orders_last_refresh_at_v1"
    private var refreshTask: Task<Void, Never>?
    private var hasLoadedCache = false

    private static var memoryOrders: [OpenOrderRecord] = []
    private static var memoryPendingOrders: [PortfolioOrder] = []
    private static var memoryUpdatedAt: String?
    private static var memorySignature = ""

    public init() {
        loadMemoryCache()
    }

    public func loadCache() {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true

        guard let cached = CacheManager.load(OpenOrdersResponse.self, key: cacheKey),
              cached.ok else {
            return
        }

        apply(cached, marksServerRefresh: false)
    }

    public static func prewarmCacheIfNeeded() async {
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

    public func loadCacheIfNeeded() async {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true

        guard let cached = await CacheManager.loadAsync(OpenOrdersResponse.self, key: cacheKey),
              cached.ok else {
            return
        }

        apply(cached, marksServerRefresh: false)
    }

    public func fetchOpenOrders() async {
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

    public func startBackgroundSync(initialDelay: Double = 0, minimumRefreshInterval: TimeInterval = 60) {
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

    public func stopBackgroundSync() {
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

