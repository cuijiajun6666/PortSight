//
//  FamilyLibrary.swift
//  PortSightKit
//
//  The 图库's photos: the family's Immich library when the pasted configuration has an `immich` part, otherwise
//  the demo library (DemoFamilyData). The months and their counts come first (one small request), so every
//  photo has a place (a slot) in the grid before it is loaded; each month's photos are fetched when it scrolls
//  into view, at most three months at a time, the most recently asked first. What has been seen is kept in the
//  caches folder, so the last library shows straight away, and also when the proxy is off.
//

import Foundation
import Observation

/// A month of the library, oldest first.
public nonisolated struct FamilyLibraryMonth: Identifiable, Hashable, Sendable, Codable {
    /// "2026-10" style without a leading zero ("2026-1"), the id the 年 / 月 cards scroll to.
    public let id: String
    public let year: Int
    public let month: Int
    public let count: Int
    /// Immich's time bucket ("2026-10-01"); nil in the demo library.
    public let timeBucket: String?

    public init(year: Int, month: Int, count: Int, timeBucket: String?) {
        self.id = "\(year)-\(month)"
        self.year = year
        self.month = month
        self.count = count
        self.timeBucket = timeBucket
    }

    public var title: String { "\(year)年\(month)月" }
}

/// One place in the grid: the `index`-th photo of a month, loaded or not.
public nonisolated struct FamilyLibrarySlot: Identifiable, Hashable, Sendable {
    public let id: String
    public let monthID: String
    public let index: Int

    public init(monthID: String, index: Int) {
        self.id = "\(monthID)#\(index)"
        self.monthID = monthID
        self.index = index
    }

    /// Reads "2026-10#3".
    public init?(id: String) {
        guard let hash = id.lastIndex(of: "#"), let index = Int(id[id.index(after: hash)...]), index >= 0 else { return nil }
        self.init(monthID: String(id[..<hash]), index: index)
    }
}

@Observable public final class FamilyLibrary {
    public nonisolated enum Status: Equatable, Sendable {
        /// No Immich configured: the demo library.
        case demo
        case connecting
        case ready
        /// Immich could not be reached or refused; the last library seen (if any) is still shown.
        case failed(ImmichError)
    }

    public static let shared = FamilyLibrary()

    public private(set) var status: Status = .demo
    /// Oldest first.
    public private(set) var months: [FamilyLibraryMonth] = []
    /// Every photo's place, oldest first.
    public private(set) var slots: [FamilyLibrarySlot] = []
    /// Photos per month id, oldest first, for the months loaded so far.
    public private(set) var loaded: [String: [FamilyPhoto]] = [:]
    /// The Immich server's host while one is configured.
    public private(set) var host: String?
    public private(set) var lastRefresh: Date?

    @ObservationIgnored private var config: ImmichConfig?
    @ObservationIgnored private var started = false
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let cacheFile: URL?
    @ObservationIgnored private let loadConfig: @MainActor () -> ImmichConfig?
    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var failedAt: [String: Date] = [:]
    /// Bumped when the configuration changes: answers for an older one are dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var refreshing: Task<Void, Never>?
    @ObservationIgnored private var saving: Task<Void, Never>?

    private static let maxConcurrentMonths = 3
    private static let maxQueuedMonths = 8
    private static let retryAfter: TimeInterval = 20
    private static let staleAfter: TimeInterval = 5 * 60

    public init(session: URLSession = FamilyLibrary.makeSession(),
                cacheFile: URL? = FamilyLibrary.defaultCacheFile,
                loadConfig: @escaping @MainActor () -> ImmichConfig? = { DriveConfig.load()?.immich }) {
        self.session = session
        self.cacheFile = cacheFile
        self.loadConfig = loadConfig
    }

    public nonisolated static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.urlCache = nil
        // Never the demo mode's offline guard: these requests are the family's own server.
        configuration.protocolClasses = configuration.protocolClasses?.filter {
            ObjectIdentifier($0) != ObjectIdentifier(DemoOfflineProtocol.self)
        }
        return URLSession(configuration: configuration)
    }

    public nonisolated static var defaultCacheFile: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FamilyLibrary", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    // MARK: Reading

    public var isRemote: Bool { host != nil }
    /// The configured Immich (address and key), for loading pictures and videos.
    public var connection: ImmichConfig? { config }
    public var totalCount: Int { months.reduce(0) { $0 + $1.count } }
    /// The newest photo, once its month is loaded (the newest month is loaded first).
    public var newestPhoto: FamilyPhoto? { months.last.flatMap { loaded[$0.id]?.last } }

    public func photo(at slot: FamilyLibrarySlot) -> FamilyPhoto? {
        guard let photos = loaded[slot.monthID], photos.indices.contains(slot.index) else { return nil }
        return photos[slot.index]
    }

    public func photo(slotID: String) -> FamilyPhoto? {
        FamilyLibrarySlot(id: slotID).flatMap(photo(at:))
    }

    /// The slot that holds this photo now, if its month is loaded (the viewer follows a photo whose place moved).
    public func slotID(ofPhoto photoID: String, inMonth monthID: String) -> String? {
        loaded[monthID]?.firstIndex { $0.id == photoID }.map { FamilyLibrarySlot(monthID: monthID, index: $0).id }
    }

    // MARK: Loading

    /// First use: reads the configuration and shows the library. Later calls refresh the months when they are a
    /// few minutes old (coming back to the 图库).
    public func start() {
        if !started {
            started = true
            reload()
        } else if isRemote, refreshing == nil,
                  lastRefresh.map({ Date().timeIntervalSince($0) > Self.staleAfter }) ?? true {
            refresh()
        }
    }

    /// Reads the configuration again (after it was pasted or cleared) and starts over. `discardingCache` drops the
    /// last library seen (a different server or key).
    public func reload(discardingCache: Bool = false) {
        started = true
        let next = loadConfig()
        generation += 1
        refreshing?.cancel()
        refreshing = nil
        queue = []
        inFlight = []
        failedAt = [:]
        lastRefresh = nil
        config = next
        host = next?.host
        guard let next else {
            removeCache()
            showDemo()
            return
        }
        if discardingCache { removeCache() }
        months = []
        slots = []
        loaded = [:]
        status = .connecting
        refresh()
        // The last library seen, read off the main thread: it can hold tens of thousands of photos.
        guard let cacheFile, !discardingCache else { return }
        let generation = generation
        let url = next.url.absoluteString
        Task { [weak self] in
            guard let cached = await Self.readCache(cacheFile, url: url) else { return }
            guard let self, generation == self.generation else { return }
            if self.months.isEmpty {
                self.months = cached.months
                self.slots = Self.slots(for: cached.months)
                self.loaded = cached.loaded
            } else {
                // The months came first: take the cached photos of months that did not change.
                var loaded = self.loaded
                for month in self.months where loaded[month.id] == nil && cached.months.contains(month) {
                    if let photos = cached.loaded[month.id], photos.count == month.count { loaded[month.id] = photos }
                }
                if loaded != self.loaded { self.loaded = loaded }
            }
        }
    }

    /// Asks Immich for the months again; months whose count changed are fetched again when seen.
    public func refresh() {
        guard let config, refreshing == nil else { return }
        let generation = generation
        if case .failed = status { status = .connecting }
        refreshing = Task { [weak self] in
            guard let self else { return }
            do {
                let (body, code) = try await self.fetch(ImmichAPI.bucketsRequest(config))
                let buckets = try ImmichAPI.parseBuckets(status: code, body: body)
                guard generation == self.generation else { return }
                self.apply(buckets)
                self.status = .ready
                self.lastRefresh = Date()
                // Reachable again: months that failed may be asked for straight away.
                self.failedAt = [:]
                if let newest = self.months.last { self.ensureLoaded(newest.id) }
            } catch is CancellationError {
            } catch {
                guard generation == self.generation else { return }
                self.status = .failed(error as? ImmichError ?? .unreachable)
            }
            if generation == self.generation { self.refreshing = nil }
        }
    }

    /// For a placeholder on screen: asks for its month now and again every so often while that fails (the proxy
    /// was off, the server was slow), until the placeholder goes (loaded, or scrolled away).
    public func keepLoading(_ monthID: String) async {
        while !Task.isCancelled {
            ensureLoaded(monthID)
            try? await Task.sleep(for: .seconds(Self.retryAfter + 1))
        }
    }

    /// Fetches a month's photos if they are not loaded yet (called as its tiles come into view).
    public func ensureLoaded(_ monthID: String) {
        guard config != nil, loaded[monthID] == nil, !inFlight.contains(monthID) else { return }
        if let failed = failedAt[monthID], Date().timeIntervalSince(failed) < Self.retryAfter { return }
        queue.removeAll { $0 == monthID }
        queue.append(monthID)
        if queue.count > Self.maxQueuedMonths { queue.removeFirst(queue.count - Self.maxQueuedMonths) }
        pump()
    }

    private func pump() {
        while inFlight.count < Self.maxConcurrentMonths, let monthID = queue.popLast() {
            guard let config, loaded[monthID] == nil,
                  let month = months.first(where: { $0.id == monthID }), let bucket = month.timeBucket else { continue }
            inFlight.insert(monthID)
            let generation = generation
            Task { [weak self] in
                guard let self else { return }
                do {
                    let (body, code) = try await self.fetch(ImmichAPI.bucketRequest(config, timeBucket: bucket))
                    let photos = try await Self.photos(status: code, body: body)
                    guard generation == self.generation else { return }
                    self.set(photos, for: monthID)
                    self.failedAt[monthID] = nil
                } catch is CancellationError {
                } catch {
                    guard generation == self.generation else { return }
                    self.failedAt[monthID] = Date()
                    if let error = error as? ImmichError, error == .unauthorized || error == .forbidden {
                        self.status = .failed(error)
                    }
                }
                guard generation == self.generation else { return }
                self.inFlight.remove(monthID)
                self.pump()
            }
        }
    }

    // MARK: Applying

    private func apply(_ buckets: [ImmichBucket]) {
        var next: [FamilyLibraryMonth] = []
        var seen = Set<String>()
        for bucket in buckets {
            guard let year = bucket.year, let month = bucket.month else { continue }
            let item = FamilyLibraryMonth(year: year, month: month, count: bucket.count, timeBucket: bucket.timeBucket)
            guard seen.insert(item.id).inserted else { continue }
            next.append(item)
        }
        next.sort { ($0.year, $0.month) < ($1.year, $1.month) }
        // Keep the photos of months that did not change.
        let previous = Dictionary(months.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var kept: [String: [FamilyPhoto]] = [:]
        for month in next where previous[month.id] == month {
            if let photos = loaded[month.id], photos.count == month.count { kept[month.id] = photos }
        }
        if next != months { months = next; slots = Self.slots(for: next) }
        if kept != loaded { loaded = kept }
        saveCache()
    }

    private func set(_ photos: [FamilyPhoto], for monthID: String) {
        if let index = months.firstIndex(where: { $0.id == monthID }), months[index].count != photos.count {
            // The month changed since its count was read: give it exactly as many places as it has photos.
            let old = months[index]
            if photos.isEmpty {
                months.remove(at: index)
            } else {
                months[index] = FamilyLibraryMonth(year: old.year, month: old.month, count: photos.count,
                                                   timeBucket: old.timeBucket)
            }
            slots = Self.slots(for: months)
        }
        loaded[monthID] = photos.isEmpty ? nil : photos
        saveCache()
    }

    private static func slots(for months: [FamilyLibraryMonth]) -> [FamilyLibrarySlot] {
        var slots: [FamilyLibrarySlot] = []
        slots.reserveCapacity(months.reduce(0) { $0 + $1.count })
        for month in months {
            for index in 0..<month.count { slots.append(FamilyLibrarySlot(monthID: month.id, index: index)) }
        }
        return slots
    }

    private func showDemo() {
        let calendar = Calendar.current
        var months: [FamilyLibraryMonth] = []
        var loaded: [String: [FamilyPhoto]] = [:]
        var order: [(year: Int, month: Int)] = []
        for photo in DemoFamilyData.photos.sorted(by: { $0.date < $1.date }) {
            let parts = calendar.dateComponents([.year, .month], from: photo.date)
            let year = parts.year ?? 0, month = parts.month ?? 0
            let id = "\(year)-\(month)"
            if loaded[id] == nil { order.append((year, month)) }
            loaded[id, default: []].append(photo)
        }
        for (year, month) in order {
            months.append(FamilyLibraryMonth(year: year, month: month, count: loaded["\(year)-\(month)"]?.count ?? 0,
                                             timeBucket: nil))
        }
        self.months = months
        self.slots = Self.slots(for: months)
        self.loaded = loaded
        status = .demo
    }

    // MARK: Network

    private func fetch(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ImmichError.badResponse }
            return (data, http.statusCode)
        } catch let error as ImmichError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ImmichError.unreachable
        }
    }

    /// Off the main thread: a month can hold a thousand photos.
    nonisolated private static func photos(status: Int, body: Data) async throws -> [FamilyPhoto] {
        var assets = try ImmichAPI.parseBucket(status: status, body: body)
        // Asked oldest first; a server that ignores `order` answers newest first.
        if let first = assets.first, let last = assets.last, first.takenAtUTC > last.takenAtUTC { assets.reverse() }
        return assets.map(photo)
    }

    /// `date` is the real moment; the remote part keeps where it was taken, so it shows in that clock time.
    nonisolated static func photo(_ asset: ImmichAsset) -> FamilyPhoto {
        FamilyPhoto(id: asset.id, date: asset.takenAtUTC,
                    peopleIDs: [], placeID: nil, caption: "", symbol: asset.isImage ? "photo" : "video", hue: 0.6,
                    isVideo: !asset.isImage, estimatedEra: nil,
                    remote: FamilyRemoteAsset(ratio: asset.ratio, durationMs: asset.durationMs,
                                              livePhotoVideoID: asset.livePhotoVideoID, city: asset.city,
                                              localOffsetHours: asset.localOffsetHours))
    }

    // MARK: Cache (no secrets: ids, dates, places)

    nonisolated private struct Cache: Codable, Sendable {
        static let currentVersion = 2
        var version = Cache.currentVersion
        let url: String
        let months: [FamilyLibraryMonth]
        let loaded: [String: [FamilyPhoto]]
    }

    nonisolated private static func readCache(_ file: URL, url: String) async -> Cache? {
        guard let data = try? Data(contentsOf: file), let cache = try? JSONDecoder().decode(Cache.self, from: data),
              cache.version == Cache.currentVersion, cache.url == url else { return nil }
        return cache
    }

    /// Written a moment after the last change, off the main thread.
    private func saveCache() {
        guard let cacheFile, let config else { return }
        saving?.cancel()
        let cache = Cache(url: config.url.absoluteString, months: months, loaded: loaded)
        saving = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(cache), !Task.isCancelled else { return }
            try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: cacheFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private func removeCache() {
        let pending = saving
        saving = nil
        pending?.cancel()
        guard let cacheFile else { return }
        try? FileManager.default.removeItem(at: cacheFile)
        // A save already past its last check could still write the file: remove it again once that one ends.
        if let pending {
            Task.detached(priority: .utility) {
                await pending.value
                try? FileManager.default.removeItem(at: cacheFile)
            }
        }
    }
}
