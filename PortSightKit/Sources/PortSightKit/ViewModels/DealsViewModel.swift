import Foundation
import Combine
@MainActor
public final class DealsViewModel: ObservableObject {
    @Published public private(set) var deals: [DealRecord] = []
    @Published public private(set) var completedOrders: [PortfolioOrder] = []
    @Published public private(set) var updatedAt: String?
    @Published public private(set) var isLoading = false
    @Published public var errorMessage: String?

    private let cacheKey = "deals_cache_v1"
    private let lastRefreshKey = "deals_last_refresh_at_v1"
    private var refreshTask: Task<Void, Never>?
    private var hasLoadedCache = false

    private static var memoryDeals: [DealRecord] = []
    private static var memoryCompletedOrders: [PortfolioOrder] = []
    private static var memoryUpdatedAt: String?
    private static var memorySignature = ""

    public init() {
        loadMemoryCache()
    }

    public func loadCache() {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true

        guard let cached = CacheManager.load(DealsResponse.self, key: cacheKey),
              cached.ok else {
            return
        }

        apply(cached, marksServerRefresh: false)
    }

    public func loadCacheIfNeeded() async {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true

        guard let cached = await CacheManager.loadAsync(DealsResponse.self, key: cacheKey),
              cached.ok else {
            return
        }

        apply(cached, marksServerRefresh: false)
    }

    public static func prewarmCacheIfNeeded() async {
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

    public func fetchDeals() async {
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

    public func startBackgroundSync(initialDelay: Double = 0, minimumRefreshInterval: TimeInterval = 60) {
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

    public func stopBackgroundSync() {
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

