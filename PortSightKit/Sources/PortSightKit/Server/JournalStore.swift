//
//  JournalStore.swift
//  PortSightKit
//
//  The /journal document (TradeJournal) for the 交易理由 part of a trade's details: read through the paired relay
//  (same bearer and HTTPS-only rules as /advice and /report) when a trade's details open, kept for 5 minutes (the
//  shadow writes at most every 15) and shared by every open card. A 404 is the relay's switch being off: it is
//  remembered as "not open yet", never shown as a failure.
//
//  The last good answer is also kept on disk (Application Support/PortSight/journal_<line>.json, with the relay it
//  came from and when), so after a relaunch without a connection the cards are still there. A failed read never
//  clears the cards on screen or on disk; only a 404 (the relay closed the feature) or forgetting / switching the
//  relay does. While the cards shown are older than the last failed read, `offlineNote` says so.
//

import Foundation
import Observation

@Observable
public final class JournalStore {
    public static let shared = JournalStore()

    public enum State: Equatable, Sendable {
        case idle
        case loading
        /// No relay paired: nothing to read.
        case unpaired
        /// 404: the relay's publishing switch is off.
        case notOpen
        /// 401: the relay no longer accepts this device.
        case needsRepair
        case failed(String)
        case loaded(TradeJournal)
    }

    /// GET <endpoint> through the paired relay (ServerStore.read), replaceable in tests.
    public typealias Reader = (RelayEndpoint, [URLQueryItem]) async throws -> Data

    /// How long an answer is reused before the next details card reads again (open cards re-read this often).
    public static let freshFor: TimeInterval = 5 * 60

    public private(set) var state: State = .idle
    /// The line read: crypto now, stock later.
    public let line: String

    @ObservationIgnored private let read: Reader
    /// The paired relay's origin, nil while unpaired.
    @ObservationIgnored private let currentBase: () -> String?
    @ObservationIgnored private var fetchedAt: Date?
    @ObservationIgnored private var fetchedFrom: String?
    @ObservationIgnored private var inFlight: (id: UUID, base: String, task: Task<Void, Never>)?
    /// Folder of the saved copy (Application Support/PortSight unless a test gives its own).
    @ObservationIgnored private let directory: URL?

    /// When the cards on screen were read from the relay (this launch, or before it for a saved copy).
    public private(set) var shownAt: Date?
    /// Why the last read failed while cards stayed on screen; nil after a good read.
    public private(set) var lastFailure: String?

    public init(line: String = "crypto", read: Reader? = nil, base: (() -> String?)? = nil, directory: URL? = nil,
                restoresSaved: Bool = true) {
        self.line = line
        self.read = read ?? { endpoint, query in try await ServerStore.shared.read(endpoint, query: query) }
        self.currentBase = base ?? {
            let server = ServerStore.shared
            return server.isPaired ? server.baseURL : nil
        }
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("PortSight", isDirectory: true)
        if restoresSaved { Task { await self.restoreSaved() } }
    }

    /// "离线：显示 14:05 保存的理由卡" while the last read failed and older cards are shown; nil otherwise.
    public var offlineNote: String? {
        guard lastFailure != nil, journal != nil, let shownAt else { return nil }
        return "离线：显示 " + Self.clock(shownAt) + " 保存的理由卡"
    }

    // MARK: Saved copy

    /// What is written to disk: the relay's raw answer, which relay, and when it was read.
    private struct Saved: Codable {
        let base: String
        let savedAt: Date
        let body: Data
    }

    private var savedURL: URL? { directory?.appendingPathComponent("journal_\(line).json") }

    /// Shows the copy saved for the relay paired now, unless something newer is already on screen. The copy is not
    /// treated as fresh: the next load still reads the relay.
    public func restoreSaved() async {
        guard let url = savedURL, let base = currentBase() else { return }
        let restored = await Task.detached(priority: .userInitiated) { () -> (Date, TradeJournal)? in
            guard let data = try? Data(contentsOf: url),
                  let saved = try? JSONDecoder().decode(Saved.self, from: data), saved.base == base,
                  let journal = try? JSONDecoder().decode(TradeJournal.self, from: saved.body) else { return nil }
            return (saved.savedAt, journal)
        }.value
        guard let (savedAt, journal) = restored, currentBase() == base, self.journal == nil else { return }
        switch state {
        case .idle, .loading, .failed:
            state = .loaded(journal)
            shownAt = savedAt
            fetchedFrom = base
            fetchedAt = nil
        default:
            break
        }
    }

    private func save(_ body: Data, base: String, at date: Date) {
        guard let url = savedURL,
              let data = try? JSONEncoder().encode(Saved(base: base, savedAt: date, body: body)) else { return }
        // Written here rather than in the background, so a reset right after can never be overtaken by the write.
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func deleteSaved() {
        guard let url = savedURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func clock(_ date: Date) -> String {
        let style = Date.FormatStyle(locale: Locale(identifier: "zh_CN"))
        return Calendar.current.isDateInToday(date)
            ? date.formatted(style.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            : date.formatted(style.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    public var journal: TradeJournal? {
        if case .loaded(let journal) = state { return journal }
        return nil
    }

    /// Reads /journal unless a recent answer from the same relay is on hand; `force` reads again (重试). Callers
    /// arriving while a read is under way wait for it; if the relay was switched meanwhile, they read the new one.
    public func load(force: Bool = false) async {
        for _ in 0..<3 {
            guard let base = currentBase() else {
                reset(to: .unpaired)
                return
            }
            let awaited: String
            if let running = inFlight {
                awaited = running.base
                await running.task.value
            } else {
                if !force, fetchedFrom == base, let fetchedAt, Date.now.timeIntervalSince(fetchedAt) < Self.freshFor { return }
                let id = UUID()
                let task = Task {
                    await self.fetch(base: base)
                    if self.inFlight?.id == id { self.inFlight = nil }
                }
                inFlight = (id, base, task)
                awaited = base
                await task.value
            }
            // The read answered for the relay still paired: done. Otherwise read the one paired now.
            if currentBase() == awaited { return }
        }
    }

    /// Forgets the cards (a different relay, or none): the next load reads from scratch. With no relay paired it
    /// says so, rather than showing a read that is not happening.
    public func reset(to next: State = .idle) {
        state = currentBase() == nil ? .unpaired : next
        fetchedFrom = nil
        fetchedAt = nil
        shownAt = nil
        lastFailure = nil
        deleteSaved()
    }

    private func fetch(base: String) async {
        // Another relay's cards are never shown as this one's; the same relay's stay up while they are re-read.
        if fetchedFrom != base || journal == nil { state = .loading }
        let next: State
        var body: Data?
        do {
            let data = try await read(.journal, [URLQueryItem(name: "line", value: line)])
            let journal = try await Task.detached(priority: .userInitiated) {
                try JSONDecoder().decode(TradeJournal.self, from: data)
            }.value
            body = data
            next = .loaded(journal)
        } catch ServerError.http(404) {
            next = .notOpen
        } catch ServerError.unauthorized {
            next = .needsRepair
        } catch ServerError.rateLimited {
            // 429: the relay (and ServerStore, for at least 30 s) holds requests back. The cards on screen stay;
            // the open pages read again only every freshFor (5 minutes), never faster.
            next = .failed("请求太频繁，稍后自动重试")
        } catch ServerError.notPaired {
            next = .unpaired
        } catch ServerError.invalidURL {
            next = .unpaired
        } catch ServerError.http(let status) {
            next = .failed("服务器返回 \(status)")
        } catch is DecodingError {
            next = .failed("服务器返回的内容读不懂")
        } catch {
            next = .failed("连不上服务器（检查网络）")
        }
        // Disconnected or switched to another relay meanwhile: drop the answer and what was on screen.
        guard currentBase() == base else {
            reset(to: currentBase() == nil ? .unpaired : .idle)
            return
        }
        switch next {
        case .loaded:
            let now = Date.now
            state = next
            fetchedFrom = base
            fetchedAt = now
            shownAt = now
            lastFailure = nil
            if let body { save(body, base: base, at: now) }
        case .notOpen:
            // The relay closed the feature: its cards are not shown, and not kept.
            state = next
            fetchedFrom = base
            fetchedAt = .now
            shownAt = nil
            lastFailure = nil
            deleteSaved()
        case .failed(let reason) where fetchedFrom == base && journal != nil:
            // Keep the last good cards on screen (and on disk); the next load tries again.
            lastFailure = reason
            fetchedAt = nil
        case .needsRepair where fetchedFrom == base && journal != nil:
            lastFailure = "需要重新配对"
            fetchedAt = nil
        default:
            state = next
            fetchedFrom = base
            fetchedAt = nil
        }
    }
}

extension JournalStore.State {
    /// What the 交易理由 part says instead of cards; nil once the journal is loaded.
    public var placeholder: (title: String, detail: String?)? {
        switch self {
        case .idle, .loading: ("正在读取交易理由…", nil)
        case .unpaired: ("还没有配对服务器", "配对 Mac mini 的中转服务后，这里显示这笔交易的理由卡。")
        case .notOpen: (JournalFormat.notOpen, "量化系统开放后，这里会自动显示每次开仓、加减仓、平仓、反手的理由。")
        case .needsRepair: ("需要重新配对", "服务器不再认这台设备的凭证，到设置里重新输入配对码。")
        case .failed(let reason): ("暂时读不到交易理由", reason)
        case .loaded: nil
        }
    }

    public var isLoading: Bool {
        switch self {
        case .idle, .loading: true
        default: false
        }
    }

    public var canRetry: Bool {
        if case .failed = self { return true }
        return false
    }
}

nonisolated extension TradeJournal {
    /// Why a trade shows no cards: it began before the covered span, or nothing matching was written meanwhile.
    public func emptyReason(symbol: String, start: Double) -> String {
        earlierNote(start) ?? "这段时间没有 " + TradeJournal.base(symbol) + " 对得上的理由卡。"
    }

    /// Said above a trade's cards when it began before the span the relay still covers, so its first cards are gone.
    public func earlierNote(_ start: Double) -> String? {
        guard startsBeforeWindow(start) else { return nil }
        return isTruncated
            ? "服务器只发最近的一部分理由卡，这笔交易开始得更早，开头的卡已经不在。"
            : "理由卡只保留最近 7 天，这笔交易开始得更早，开头的卡已经不在。"
    }
}
