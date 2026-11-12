//
//  RelayFeedStore.swift
//  PortSightKit
//
//  One relay document kept for the pages: read through the paired relay (ServerStore.read: bearer, HTTPS, back-off
//  and pair-again rules), saved to disk after every good read so it stays on screen offline and after a restart,
//  and dropped only when the relay is unpaired or replaced (ServerStore.clearData → reset()). A 404 means the Mac
//  mini has not opened the endpoint yet; {"available": false, "message": …} means it is not ready. Neither is shown
//  as a failure. Used by /notices, /calendar, /news, /ibkr/status and /account (personal IBKR).
//

import Foundation
import Observation

/// What a fetch found: the document, or the relay saying the endpoint is not ready yet.
public nonisolated enum RelayFetchResult<Document: Sendable>: Sendable {
    case document(Document)
    case unavailable(String?)
}

@Observable
public final class RelayFeedStore<Document: Codable & Sendable> {
    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        /// No relay paired.
        case unpaired
        /// 404: the relay does not offer this yet.
        case notOpen
        /// {"available": false}: offered, but nothing to show yet (the relay's message, if any).
        case unavailable(String?)
        /// 401: the relay no longer accepts this device.
        case needsRepair
        /// Too many requests, or locked out for a while: retried later on its own.
        case rateLimited
        case failed(String)
        case loaded
    }

    /// Reads one relay endpoint (ServerStore.read in the app; replaced in tests).
    public typealias Reader = (RelayEndpoint, [URLQueryItem]) async throws -> Data
    public typealias Fetch = (_ read: Reader) async throws -> RelayFetchResult<Document>

    public private(set) var phase: Phase = .idle
    /// The last good document, from this session or from disk.
    public private(set) var document: Document?
    /// When `document` was read from the relay (survives a restart).
    public private(set) var readAt: Date?
    /// True while `document` is older than the last attempt (the last read failed or came from disk).
    public private(set) var isSaved = false

    /// Shortest gap between automatic reads; `force` ignores it.
    public let minInterval: TimeInterval
    /// After a failed read the next one may come this soon (not a whole `minInterval` later).
    public let retryAfterFailure: TimeInterval

    @ObservationIgnored private let cacheName: String?
    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let read: Reader
    @ObservationIgnored private let currentBase: () -> String?
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var loadedFrom: String?
    @ObservationIgnored private var inFlight: (id: UUID, base: String, task: Task<Void, Never>)?

    /// - Parameters:
    ///   - cacheName: file name under Application Support/PortSight; nil keeps nothing on disk.
    ///   - minInterval: shortest gap between reads unless forced.
    public init(cacheName: String?, minInterval: TimeInterval, retryAfterFailure: TimeInterval = 30, read: Reader? = nil,
                base: (() -> String?)? = nil, fetch: @escaping Fetch) {
        self.cacheName = cacheName
        self.minInterval = minInterval
        self.retryAfterFailure = min(retryAfterFailure, minInterval)
        self.fetch = fetch
        self.read = read ?? { endpoint, query in try await ServerStore.shared.read(endpoint, query: query) }
        self.currentBase = base ?? {
            let server = ServerStore.shared
            return server.isPaired ? server.baseURL : nil
        }
        restore()
    }

    /// Reads the endpoint unless it was read less than `minInterval` ago from the same relay; `force` reads now.
    /// Callers arriving while a read is under way wait for it.
    public func load(force: Bool = false) async {
        guard let base = currentBase() else {
            reset(to: .unpaired)
            return
        }
        if let running = inFlight {
            await running.task.value
            if running.base == base { return }
        }
        if loadedFrom != nil, loadedFrom != base { reset() }
        if !force, let lastAttempt, Date.now.timeIntervalSince(lastAttempt) < minInterval { return }
        lastAttempt = .now
        let id = UUID()
        let task = Task {
            await self.perform(base: base)
            if self.inFlight?.id == id { self.inFlight = nil }
        }
        inFlight = (id, base, task)
        await task.value
    }

    /// Forgets the document (unpaired, or another relay) and its saved copy.
    public func reset(to next: Phase = .idle) {
        phase = currentBase() == nil ? .unpaired : next
        document = nil
        readAt = nil
        isSaved = false
        loadedFrom = nil
        lastAttempt = nil
        if let url = cacheURL { try? FileManager.default.removeItem(at: url) }
    }

    /// For tests and previews: a document as if just read.
    public func show(_ document: Document, readAt: Date = .now) {
        self.document = document
        self.readAt = readAt
        isSaved = false
        phase = .loaded
        loadedFrom = currentBase()
    }

    private func perform(base: String) async {
        let before = phase
        if document == nil { phase = .loading }
        let next: Phase
        var fresh: Document?
        do {
            switch try await fetch(read) {
            case .document(let value):
                fresh = value
                next = .loaded
            case .unavailable(let message):
                next = .unavailable(message)
            }
        } catch ServerError.http(404) {
            next = .notOpen
        } catch ServerError.unauthorized {
            next = .needsRepair
        } catch ServerError.notPaired, ServerError.invalidURL {
            next = .unpaired
        } catch ServerError.rateLimited {
            next = .rateLimited
        } catch ServerError.http(403) {
            next = .failed("服务器暂时拒绝了这项请求（403），稍后自动再试")
        } catch ServerError.http(let status) {
            next = .failed("服务器返回 \(status)")
        } catch is DecodingError {
            next = .failed("服务器返回的内容读不懂")
        } catch let error where RelayAPI.isCancellation(error) {
            // Called off on this side: not a failure; what was shown stays and the next read may come at once.
            if phase == .loading { phase = before == .loading ? .idle : before }
            lastAttempt = nil
            return
        } catch {
            next = .failed("连不上服务器（检查网络）")
        }
        // Unpaired or switched relay meanwhile: drop the answer.
        guard currentBase() == base else { return }
        switch next {
        case .loaded:
            document = fresh
            readAt = .now
            isSaved = false
            loadedFrom = base
            phase = .loaded
            save(base: base)
        case .notOpen, .unavailable:
            // The relay says there is nothing (yet): what was shown no longer applies.
            document = nil
            readAt = nil
            isSaved = false
            loadedFrom = base
            phase = next
            if let url = cacheURL { try? FileManager.default.removeItem(at: url) }
        default:
            // A failed read keeps the last good document on screen and on disk, and is tried again soon.
            if document != nil { isSaved = true }
            phase = next
            lastAttempt = Date.now.addingTimeInterval(retryAfterFailure - minInterval)
        }
    }

    // MARK: Disk

    private struct Saved: Codable {
        var base: String
        var readAt: Date
        var document: Document
    }

    private var cacheURL: URL? { cacheName.map { RelayCache.directory.appendingPathComponent($0) } }

    private func save(base: String) {
        guard let url = cacheURL, let document, let readAt,
              let data = try? JSONEncoder().encode(Saved(base: base, readAt: readAt, document: document)) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func restore() {
        guard let url = cacheURL, let base = currentBase(), let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(Saved.self, from: data), saved.base == base else { return }
        document = saved.document
        readAt = saved.readAt
        isSaved = true
        loadedFrom = base
        phase = .loaded
    }
}

extension RelayFeedStore.Phase {
    /// Something the page can show instead of the document; nil once loaded.
    public func placeholder(notOpen: String = "尚未开放") -> (title: String, detail: String?)? {
        switch self {
        case .idle, .loading: ("正在读取…", nil)
        case .unpaired: ("还没有配对服务器", "在设置里配对 Mac mini 后显示。")
        case .notOpen: (notOpen, nil)
        case .unavailable(let message): (message ?? "暂无数据", nil)
        case .needsRepair: ("需要重新配对", "服务器不再认这台设备的凭证，到设置里重新输入配对码。")
        case .rateLimited: ("请求太频繁", "稍后会自动再试。")
        case .failed(let reason): ("暂时读不到", reason)
        case .loaded: nil
        }
    }

    public var isLoading: Bool { self == .idle || self == .loading }
}

/// Reads `{"available": false, "message": …}` ahead of a document's own decoding.
nonisolated enum RelayAvailability {
    static func unavailableMessage(_ data: Data) -> String?? {
        guard let document = try? JSONDecoder().decode(RelayDocument.self, from: data), document.available == false else {
            return nil
        }
        return .some(document.message)
    }
}
