//
//  ServerConnection.swift
//  PortSight
//
//  Read-only connection to the quant relay on the Mac mini (quant_system/relay), reached over its public HTTPS address
//  HTTPS: no public port. Read-only, except POST /devices (pairing with the relay's one-time code from
//  `python3 -m quant_system.relay pair`, then this device's APNs token). The device token it returns lives only in
//  the keychain (iOS and macOS), scoped to the exact relay origin, and is never logged. Requests are built in
//  RelayAPI.swift.
//

import Foundation
import Security
import Combine

public enum ServerKeychain {
    private static func query(service: String, account: String) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        #if os(macOS)
        // The Mac app uses the same iOS-style keychain, so the accessibility class below is honoured there too.
        q[kSecUseDataProtectionKeychain as String] = true
        #endif
        return q
    }

    public static func read(service: String, account: String) -> String? {
        var q = query(service: service, account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// AfterFirstUnlock: background refresh must be able to read it while the phone is locked.
    @discardableResult
    public static func save(_ value: String, service: String, account: String) -> Bool {
        let q = query(service: service, account: account)
        let fields: [String: Any] = [kSecValueData as String: Data(value.utf8),
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(q as CFDictionary, fields as CFDictionary)
        if status == errSecItemNotFound {
            var item = q
            fields.forEach { item[$0.key] = $0.value }
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    public static func delete(service: String, account: String) {
        SecItemDelete(query(service: service, account: account) as CFDictionary)
    }
}

public nonisolated final class ServerNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum ServerError: Error {
    case invalidURL, notPaired, http(Int), invalidResponse
    /// 401 from the relay: the device token was revoked or the relay forgot this device. Pair again; nothing is
    /// sent until then (more than 10 401s in 10 minutes lock this source out for 10 minutes).
    case unauthorized
    /// 429 (120 requests a minute per source): nothing is sent until the back-off ends.
    case rateLimited
}

@MainActor
public final class ServerStore: ObservableObject {
    public static let shared = ServerStore()
    public static let urlKey = "server.relayURL"
    public static let keychainService = "PortSight.relay"

    @Published public private(set) var host: HostStatus?
    /// The newest 50 synced /alerts events, newest first, for the page.
    @Published public private(set) var events: [HostEvent] = []
    /// Up to 500 synced events, newest first: push look-ups and 同类告警 history, also offline.
    public private(set) var syncedEvents: [HostEvent] = []
    @Published public private(set) var fetchedAt: Date?
    @Published public private(set) var lastFailure: Date?
    /// Why the last refresh failed (nil after a good one): the banners tell a network failure from the server
    /// refusing or rate-limiting this device.
    @Published public private(set) var failure: RelayFailure?
    /// No request is sent before this (after a 429, or a refused pairing).
    @Published public private(set) var blockedUntil: Date?
    /// Endpoints the server refused (403) and when they may be asked again (10 minutes later).
    private var pathBlockedUntil: [String: Date] = [:]
    @Published public private(set) var busy = false
    /// The round trip of the last /host read that got through, in ms: the connection's real latency, shown as
    /// 「N ms」. Only /host counts, so one refresh changes it once (not again for each IBKR read that follows).
    @Published public private(set) var latencyMs: Int?
    @Published public private(set) var isSample = false
    @Published public private(set) var pairingState: RelayPairingState = .unpaired
    /// /status, /account, /reports/latest and /advice (RelayEndpoint.pending), read with each refresh.
    @Published public private(set) var feeds: [RelayEndpoint: RelayFeedState] = [:]
    @Published public var message: String?
    @Published public var pushStatus: String?

    /// Set by a 401 on any request; cleared only by pairing again or forgetting the relay. Kept across launches
    /// (with the relay it belongs to), so a revoked device never sends again after a restart.
    private var needsRepair = false {
        didSet {
            if needsRepair { UserDefaults.standard.set(baseURL, forKey: Self.repairKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.repairKey) }
        }
    }
    static let repairKey = "server.needsRepairFor"
    /// The APNs token (and relay) the relay refused with a 400: not sent again until it changes or the device pairs.
    static let rejectedPushKey = "server.pushRejected"
    /// When the pending endpoints were last checked (at most every RelayAPI.pendingFeedsInterval).
    private var lastFeedsRead: Date?
    /// When the last automatic refresh started: they are kept at least `RelayAPI.minRefreshInterval` apart.
    private var lastAttempt: Date?

    private let session = URLSession(configuration: .ephemeral, delegate: ServerNoRedirect(), delegateQueue: nil)

    public var baseURL: String { UserDefaults.standard.string(forKey: Self.urlKey) ?? "" }
    public var isPaired: Bool { !baseURL.isEmpty && ServerKeychain.read(service: Self.keychainService, account: baseURL) != nil }

    /// Minutes after which the page shows the "not updated" banner (the server's value, 15 by default).
    public var staleAfterMinutes: Double { host?.stale_after_minutes ?? 15 }

    /// The four volumes for the 云盘 and 存储 pages, from the same /host document as the server page (the sample
    /// until paired). nil while there is no disk data.
    public var volumes: [StorageVolume]? {
        guard let host, host.hasData, let disks = host.disks, disks.values.contains(where: { $0 != nil }) else { return nil }
        return StorageVolume.volumes(from: host)
    }

    public func freshness(now: Date = .now) -> ServerFreshness {
        ServerFreshness.evaluate(asOf: host?.as_of, now: now, staleAfterMinutes: staleAfterMinutes)
    }

    /// The connection banner (offline, rate-limited, server error, stale heartbeat), nil when all is well.
    /// `networkHint`: "手机网络" on iOS, "网络" on the Mac.
    public func connectionBanner(now: Date = .now, networkHint: String) -> RelayConnectionBanner? {
        RelayConnectionBanner.make(failure: lastFailure == nil ? nil : failure, networkHint: networkHint,
                                   savedAt: fetchedAt, hasData: host != nil, freshness: freshness(now: now),
                                   staleAfterMinutes: staleAfterMinutes, blockedUntil: blockedUntil,
                                   reachedServer: reachedRecently(now: now))
    }

    /// How this device reaches the Mac mini, measured: the public HTTPS address (Tailscale Funnel), the last read's
    /// round trip and when the relay was last read. Before pairing, the sample connection the sample page shows.
    public var connection: ConnectionStatus {
        guard isPaired, !isSample else { return DemoConnection.owner }
        let offline = lastFailure != nil && failure == .network
        return ConnectionStatus(path: offline ? .offline : .relayed, relayName: ConnectionStatus.funnel,
                                latencyMs: offline ? nil : latencyMs, lastSync: fetchedAt, queuedUploads: 0,
                                serverName: "Mac mini", serverPlace: "悉尼")
    }

    /// A refresh got through within the last few minutes: the server is known to be up right now.
    public func reachedRecently(now: Date = .now) -> Bool {
        guard lastFailure == nil, let fetchedAt else { return false }
        return now.timeIntervalSince(fetchedAt) < 3 * 60
    }

    /// The relay is the one live connection in demo mode (DemoPortfolioData.enabled): once paired, this store reads
    /// the real Mac mini; until then the page shows the sample document.
    public init() {
        if isPaired {
            needsRepair = UserDefaults.standard.string(forKey: Self.repairKey) == baseURL
            loadCache()
        } else if DemoPortfolioData.enabled {
            showSample()
        }
        updateState()
    }

    /// https only, a host, no credentials / path / query: the token is bound to exactly this origin.
    public static func normalizedURL(_ value: String) -> String? {
        guard let parts = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { return nil }
        return "https://\(host.lowercased())" + (parts.port.map { ":\($0)" } ?? "")
    }

    /// POST /devices with the one-time code. The APNs token goes along when pushes are on (else "").
    public func pair(url: String, code: String) async -> Bool {
        guard let base = Self.normalizedURL(url) else {
            message = "地址只能是 https:// 开头的服务器地址，例如 https://mac-mini.xxxx.ts.net"
            return false
        }
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { message = "请输入配对码"; return false }
        if let blockedUntil, blockedUntil > .now {
            message = "服务器让这台设备暂停请求，\(ServerDates.clock(blockedUntil)) 后再试。"
            return false
        }
        let apns = ServerPushSettings.enabled ? (ServerPushSettings.token ?? "") : ""
        guard let request = RelayAPI.pairingRequest(base: base, code: code, apnsToken: apns) else {
            message = "地址格式不对"
            return false
        }
        busy = true
        defer { busy = false }
        let data: Data
        do {
            let (body, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ServerError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                if let wait = RelayAPI.backoff(status: http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After")) {
                    let until = Date.now.addingTimeInterval(wait)
                    blockedUntil = until
                    message = (http.statusCode == 403 ? "服务器拒绝了配对请求（403）" : "请求太频繁")
                        + "，\(ServerDates.clock(until)) 后再试。"
                } else {
                    message = RelayAPI.pairingFailure(status: http.statusCode)
                }
                return false
            }
            data = body
        } catch {
            message = "配对失败：连不上服务器。检查网络和地址是否正确。"
            return false
        }
        guard let token = RelayAPI.deviceToken(from: data) else {
            message = "配对失败：服务器的回复里没有设备凭证。"
            return false
        }
        let previous = baseURL
        guard ServerKeychain.save(token, service: Self.keychainService, account: base) else {
            message = "配对失败：设备凭证没能存进钥匙串，请重试。"
            return false
        }
        if previous != base || isSample {
            // A different server, a first pairing or the sample on screen: start from nothing, so neither another
            // server's data nor the sample is ever shown as this server's (the first refresh below can fail).
            if !previous.isEmpty, previous != base { ServerKeychain.delete(service: Self.keychainService, account: previous) }
            clearData()
        }
        UserDefaults.standard.set(base, forKey: Self.urlKey)
        needsRepair = false
        UserDefaults.standard.removeObject(forKey: Self.rejectedPushKey)
        ServerPushSettings.deliveredTo = apns.isEmpty ? nil : base
        if !apns.isEmpty { pushStatus = "令牌已交给服务器（\(ServerDates.clock(.now))）" }
        isSample = false
        updateState()
        busy = false
        if await refresh(force: true) {
            message = "配对成功"
        } else if pairingState != .needsRepair {
            message = "配对成功，但暂时读不到数据，稍后会自动重试。"
        }
        return true
    }

    /// Unpair: tell the relay to stop pushing here (best effort), then forget the device token and the data.
    public func forget() async {
        if isPaired, ServerPushSettings.deliveredTo == baseURL { _ = await deliver("") }
        if !baseURL.isEmpty { ServerKeychain.delete(service: Self.keychainService, account: baseURL) }
        UserDefaults.standard.removeObject(forKey: Self.urlKey)
        ServerPushSettings.deliveredTo = nil
        needsRepair = false
        UserDefaults.standard.removeObject(forKey: Self.rejectedPushKey)
        clearData()
        if DemoPortfolioData.enabled { showSample() }
        updateState()
        message = "已断开"
        pushStatus = nil
    }

    /// GET /host and the last 7 days of /alerts. Returns false when the relay could not be read; what was read
    /// before stays on screen and on disk. Automatic refreshes come at most every 30 s (`force`: a tap or pull).
    @discardableResult
    public func refresh(force: Bool = false) async -> Bool {
        guard isPaired else {
            // Leave a sample already on screen (and the message under it, e.g. a pairing error) as it is.
            if DemoPortfolioData.enabled { if !isSample { showSample() } } else { message = "还没有配对服务器" }
            updateState()
            return false
        }
        if isSample {
            // Paired, but the sample came up while the keychain was still locked: show this server's saved data.
            isSample = false
            host = nil
            events = []
            syncedEvents = []
            loadCache()
        }
        updateState()
        guard !busy else { return false }
        if !force, let lastAttempt, Date.now.timeIntervalSince(lastAttempt) < RelayAPI.minRefreshInterval {
            return lastFailure == nil && fetchedAt != nil
        }
        lastAttempt = .now
        busy = true
        defer { busy = false }
        // Answers for a server that was disconnected or replaced meanwhile are dropped.
        let base = baseURL
        do {
            let h: HostStatus = try await get(.host)
            let alerts = await fetchAlerts()
            guard baseURL == base else { return false }
            // /alerts may have been refused after /host got through: stop, do not read the feeds.
            if needsRepair { throw ServerError.unauthorized }
            host = h
            if let alerts { keep(alerts) }
            fetchedAt = .now
            lastFailure = nil
            failure = nil
            isSample = false
            saveCache()
        } catch ServerError.unauthorized {
            guard baseURL == base else { return false }
            lastFailure = .now
            failure = .unauthorized
            needsRepair = true
            updateState()
            message = Self.repairMessage
            return false
        } catch {
            guard baseURL == base else { return false }
            // Called off on this side (a pull-to-refresh SwiftUI ended early): not 连接失败. Nothing changes and
            // the next refresh may come at once.
            if RelayAPI.isCancellation(error) {
                lastAttempt = nil
                return false
            }
            // The banner says what happened; the data read before stays.
            lastFailure = .now
            failure = RelayFailure(error)
            // The personal IBKR account does not depend on /host: a /host that failed (a 403, a 5xx) must not
            // leave 资产 without its figures. Unreachable or rate-limited, these fail fast too.
            busy = false
            await IBKRStore.shared.refreshStatus()
            await IBKRStore.shared.refreshAccount()
            return false
        }
        busy = false
        if force || lastFeedsRead.map({ Date.now.timeIntervalSince($0) >= RelayAPI.pendingFeedsInterval }) ?? true {
            lastFeedsRead = .now
            await refreshFeeds()
        }
        saveCache()
        // Notices, the calendar and news (each at most every 30 s / 5 min), and the IBKR login state.
        await RelayNotices.store.load()
        await RelayMarket.calendar.load()
        await RelayMarket.news.load()
        await IBKRStore.shared.refreshStatus()
        // The personal IBKR account is the portfolio on 总览 / 资产 once paired (at most every 5 s), and its
        // fills, orders and cash (only what is new; at most every 10 s).
        await IBKRStore.shared.refreshAccount()
        await IBKRActivityStore.shared.refresh()
        // The account's value curve for the default range (a 304 when nothing changed).
        await IBKREquityStore.shared.load(.standard)
        // Icons: download those of new assets, delete those of assets that are gone (the rest stay on the device).
        await SymbolLogoStore.shared.sync(SymbolLogoStore.symbolsInUse())
        await syncPushToken()
        return true
    }

    /// Reads the pending endpoints. Only `available` / `as_of` are looked at until their pages exist.
    private func refreshFeeds() async {
        let base = baseURL
        var next = feeds
        func failed(_ endpoint: RelayEndpoint, _ state: RelayFeedState) {
            // A failed read keeps the last good answer.
            if next[endpoint]?.isGood != true { next[endpoint] = state }
        }
        for endpoint in RelayEndpoint.pending {
            do {
                let document: RelayDocument = try await get(endpoint)
                next[endpoint] = RelayFeedState(document)
            } catch ServerError.unauthorized {
                // Every other read would fail the same way and count towards the lockout: stop here.
                failed(endpoint, .needsRepair)
                break
            } catch ServerError.rateLimited {
                failed(endpoint, .failed("请求太频繁"))
                break
            } catch ServerError.http(let status) {
                failed(endpoint, .failed("HTTP \(status)"))
            } catch is DecodingError {
                failed(endpoint, .failed("返回的不是 JSON"))
            } catch {
                failed(endpoint, .failed("连不上"))
            }
        }
        guard baseURL == base else { return }
        feeds = next
    }

    /// Pages read per sync at most (500 events each), so a runaway cursor cannot loop forever.
    static let maxAlertPages = 20

    /// GET /alerts again (see fetchAlerts): keeps the newest 50 for the page and returns every event fetched; nil when
    /// not paired or a page failed (the page keeps what it had).
    @discardableResult
    public func syncAlerts() async -> [HostEvent]? {
        guard isPaired, let all = await fetchAlerts() else { return nil }
        keep(all)
        saveCache()
        return all
    }

    /// The last 7 days of /alerts, oldest first: the first page by `since`, then `next_cursor` while the relay says
    /// `has_more` (a page holds at most 500, the oldest first, so the newest events are on the last page).
    /// refresh() and syncAlerts() both read it this way, so neither puts an older page back on screen.
    private func fetchAlerts() async -> [HostEvent]? {
        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7 * 86400))
        var query = [URLQueryItem(name: "since", value: since)]
        var all: [HostEvent] = []
        for _ in 0..<Self.maxAlertPages {
            guard let page: HostAlertPage = try? await get(.alerts, query: query) else { return nil }
            all += page.events
            guard page.has_more == true, let cursor = page.next_cursor, !cursor.isEmpty else { break }
            query = [URLQueryItem(name: "cursor", value: cursor)]
        }
        return all
    }

    /// Keeps the newest 500 synced events (newest first) and shows the newest 50.
    private func keep(_ oldestFirst: [HostEvent]) {
        syncedEvents = Array(oldestFirst.suffix(RelayCache.maxEvents).reversed())
        events = Array(syncedEvents.prefix(50))
    }

    // MARK: push

    /// A new APNs token from the system (every launch while pushes are on, and whenever it changes).
    public func pushTokenArrived(_ token: String) async {
        if isPushRejected(token) { return }
        if ServerPushSettings.token != token {
            ServerPushSettings.token = token
            ServerPushSettings.deliveredTo = nil
            updateState()
        }
        await uploadPushToken(token)
    }

    /// The push switch was turned off: the relay gets "" and stops pushing to this device.
    public func pushTurnedOff() async {
        ServerPushSettings.token = nil
        await uploadPushToken("")
    }

    /// POST /devices with the device bearer: the relay stores (or, with "", forgets) this device's APNs token.
    public func uploadPushToken(_ token: String) async {
        guard isPaired else {
            pushStatus = token.isEmpty ? nil : "先配对服务器，推送令牌才能交给服务器"
            return
        }
        switch await deliver(token) {
        case .success:
            pushStatus = token.isEmpty ? "已停止向这台设备推送" : "令牌已交给服务器（\(ServerDates.clock(.now))）"
        case .failure(let error):
            switch error as? ServerError {
            case .unauthorized?: pushStatus = Self.repairMessage
            case .http(400)?:
                // A 400 counts as an auth failure on the relay: never resend this token by itself.
                UserDefaults.standard.set(baseURL + "|" + token, forKey: Self.rejectedPushKey)
                pushStatus = "令牌格式不对（400），服务器没有接受；换了令牌或重新配对后再交"
            case .rateLimited?: pushStatus = "请求太频繁，稍后会自动再试"
            default: pushStatus = token.isEmpty ? "没能通知服务器停止推送：连上服务器后会自动再试"
                                                : "令牌没交上去：连上服务器后会自动再试"
            }
        }
    }

    /// After a good refresh: hand over a token the relay does not have yet, or withdraw one it should not have.
    private func syncPushToken() async {
        let delivered = ServerPushSettings.deliveredTo == baseURL
        if ServerPushSettings.enabled, let token = ServerPushSettings.token, !delivered, !isPushRejected(token) {
            await uploadPushToken(token)
        } else if !ServerPushSettings.enabled, delivered {
            await uploadPushToken("")
        }
    }

    private func isPushRejected(_ token: String) -> Bool {
        UserDefaults.standard.string(forKey: Self.rejectedPushKey) == baseURL + "|" + token
    }

    private func deliver(_ apnsToken: String) async -> Result<Void, Error> {
        if let refusal = refusal() { return .failure(refusal) }
        guard let base = Self.normalizedURL(baseURL), base == baseURL,
              let device = ServerKeychain.read(service: Self.keychainService, account: base),
              let request = RelayAPI.registerRequest(base: base, deviceToken: device, apnsToken: apnsToken) else {
            return .failure(ServerError.notPaired)
        }
        do {
            let data = try await perform(request)
            guard RelayAPI.isRegistered(data) else { throw ServerError.invalidResponse }
            ServerPushSettings.deliveredTo = apnsToken.isEmpty ? nil : base
            updateState()
            return .success(())
        } catch {
            if case ServerError.unauthorized = error, baseURL == base {
                needsRepair = true
                updateState()
            }
            return .failure(error)
        }
    }

    // MARK: reads

    /// POST /ibkr/reauth (IBKRStore.reauthorize). Returns the status and body. A 401 means pair again and a 403
    /// pauses this action like any refused endpoint; a 429 here means the login was asked for moments ago, so it
    /// does not pause the other reads.
    public func postIBKRReauth() async throws -> (status: Int, body: Data) {
        if let refusal = refusal(path: "/ibkr/reauth") { throw refusal }
        guard let base = Self.normalizedURL(baseURL), base == baseURL else { throw ServerError.invalidURL }
        guard let token = ServerKeychain.read(service: Self.keychainService, account: base) else { throw ServerError.notPaired }
        guard let request = RelayAPI.ibkrReauthRequest(base: base, deviceToken: token) else { throw ServerError.invalidURL }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServerError.invalidResponse }
        switch http.statusCode {
        case 401:
            needsRepair = true
            updateState()
            throw ServerError.unauthorized
        case 403:
            pathBlockedUntil["/ibkr/reauth"] = Date.now.addingTimeInterval(RelayAPI.lockoutWait)
            throw ServerError.http(403)
        default:
            return (http.statusCode, data)
        }
    }

    /// Raw body of a relay GET (every endpoint needs the device bearer). A 401 throws ServerError.unauthorized and
    /// marks the pairing as needing repair; after that, and during a back-off, nothing is sent.
    public func read(_ endpoint: RelayEndpoint, query: [URLQueryItem] = []) async throws -> Data {
        if let refusal = refusal(path: endpoint.rawValue) { throw refusal }
        guard let base = Self.normalizedURL(baseURL), base == baseURL else { throw ServerError.invalidURL }
        guard let token = ServerKeychain.read(service: Self.keychainService, account: base) else { throw ServerError.notPaired }
        guard let request = RelayAPI.readRequest(base: base, endpoint: endpoint, deviceToken: token, query: query) else {
            throw ServerError.invalidURL
        }
        return try await perform(request)
    }

    public func get<T: Decodable>(_ endpoint: RelayEndpoint, query: [URLQueryItem] = []) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await read(endpoint, query: query))
    }

    public func showSample() {
        guard let data = ServerSample.json.data(using: .utf8),
              let h = try? JSONDecoder().decode(HostStatus.self, from: data) else { return }
        host = h
        events = h.alerts_recent ?? []
        syncedEvents = []
        isSample = true
        message = nil
    }

    static let repairMessage = "需要重新配对：服务器不再认这台设备的凭证。到设置里重新输入配对码。"

    /// Why no request may be sent now: the device must pair again, the server asked this source to slow down (429,
    /// every endpoint), or it refused this endpoint (403, that endpoint only: one forbidden path never stops the rest,
    /// and is not asked again for 10 minutes, so it is never hammered).
    private func refusal(path: String? = nil, now: Date = .now) -> ServerError? {
        if needsRepair { return .unauthorized }
        if let blockedUntil, blockedUntil > now { return .rateLimited }
        if let path, let until = pathBlockedUntil[path], until > now { return .http(403) }
        return nil
    }

    /// Reads small enough that their round trip is the connection's latency (not a large download).
    static let latencyPaths: Set<String> = ["/host"]

    // (readConditional's answer: RelayConditionalRead, in IBKREquity.swift.)

    /// GET with If-None-Match: `.notModified` when the relay answers 304 (nothing new since `etag`), else the body
    /// and the new ETag. Every other answer is handled like `read` (401 → pair again, 429 / 403 back off).
    public func readConditional(_ endpoint: RelayEndpoint, query: [URLQueryItem] = [],
                                etag: String?) async throws -> RelayConditionalRead {
        if let refusal = refusal(path: endpoint.rawValue) { throw refusal }
        guard let base = Self.normalizedURL(baseURL), base == baseURL else { throw ServerError.invalidURL }
        guard let token = ServerKeychain.read(service: Self.keychainService, account: base) else { throw ServerError.notPaired }
        guard var request = RelayAPI.readRequest(base: base, endpoint: endpoint, deviceToken: token, query: query) else {
            throw ServerError.invalidURL
        }
        if let etag, !etag.isEmpty { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, http) = try await send(request)
        if http.statusCode == 304 { return .notModified }
        let body = try check(http, data: data)
        return .changed(body, etag: http.value(forHTTPHeaderField: "ETag"))
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, http) = try await send(request)
        return try check(http, data: data)
    }

    /// Sends the request, keeps the back-off rules and the latency; the status is looked at by the caller.
    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let started = ContinuousClock.now
        let (data, response) = try await session.data(for: request)
        let elapsed = ContinuousClock.now - started
        guard let http = response as? HTTPURLResponse else { throw ServerError.invalidResponse }
        if let wait = RelayAPI.backoff(status: http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After")) {
            if http.statusCode == 403 {
                pathBlockedUntil[request.url?.path ?? ""] = Date.now.addingTimeInterval(wait)
            } else {
                blockedUntil = Date.now.addingTimeInterval(wait)
            }
        }
        if http.statusCode == 200 || http.statusCode == 304, let path = request.url?.path, Self.latencyPaths.contains(path) {
            latencyMs = max(1, Int((elapsed / .milliseconds(1)).rounded()))
        }
        return (data, http)
    }

    private func check(_ http: HTTPURLResponse, data: Data) throws -> Data {
        switch http.statusCode {
        case 200:
            return data
        case 401:
            // Retrying would only add auth failures (10 in 10 minutes lock this source): stop until paired again.
            needsRepair = true
            updateState()
            throw ServerError.unauthorized
        case 429:
            throw ServerError.rateLimited
        default:
            throw ServerError.http(http.statusCode)
        }
    }

    private func updateState() {
        let state: RelayPairingState
        if !isPaired {
            state = .unpaired
        } else if needsRepair {
            state = .needsRepair
        } else if ServerPushSettings.enabled, ServerPushSettings.token != nil, ServerPushSettings.deliveredTo == baseURL {
            state = .pushDelivered
        } else {
            state = .paired
        }
        if pairingState != state { pairingState = state }
    }

    /// Re-reads the push switch after the settings page changed it.
    public func pushSwitchChanged() { updateState() }

    private func clearData() {
        host = nil; events = []; syncedEvents = []; feeds = [:]; fetchedAt = nil; lastFailure = nil; failure = nil
        blockedUntil = nil; lastAttempt = nil; lastFeedsRead = nil; pathBlockedUntil = [:]; latencyMs = nil
        isSample = false
        JournalStore.shared.reset()
        RelayNotices.store.reset()
        RelayMarket.calendar.reset()
        RelayMarket.news.reset()
        IBKRStore.shared.reset()
        IBKRActivityStore.shared.reset()
        IBKREquityStore.shared.reset()
        RelayCache.delete(at: Self.cacheURL)
        try? FileManager.default.removeItem(at: Self.legacyCacheURL)
    }

    // The last good copy of everything read (host, synced alerts, feeds, when), so the pages keep it offline and
    // after a restart. Written only after a good read for the relay still paired; deleted only by clearData().
    static var cacheURL: URL { RelayCache.directory.appendingPathComponent("server_cache.json") }
    /// Before the full cache: /host alone.
    private static var legacyCacheURL: URL { RelayCache.directory.appendingPathComponent("server_host.json") }

    private func saveCache() {
        guard let host, !isSample, isPaired else { return }
        RelayCache(base: baseURL, host: host, events: syncedEvents, feeds: feeds, fetchedAt: fetchedAt)
            .save(to: Self.cacheURL)
    }

    private func loadCache() {
        if let cache = RelayCache.load(from: Self.cacheURL), cache.base == baseURL {
            host = cache.host
            syncedEvents = cache.events
            events = cache.events.isEmpty ? (cache.host?.alerts_recent ?? []) : Array(cache.events.prefix(50))
            feeds = cache.feedStates
            fetchedAt = cache.fetchedAt
            return
        }
        guard let data = try? Data(contentsOf: Self.legacyCacheURL),
              let h = try? JSONDecoder().decode(HostStatus.self, from: data) else { return }
        host = h
        events = h.alerts_recent ?? []
    }
}

/// What ServerStore keeps on disk between launches (see ServerStore.saveCache).
public nonisolated struct RelayCache: Codable, Equatable, Sendable {
    public static let maxEvents = 500

    public var base: String
    public var host: HostStatus?
    /// Newest first, at most `maxEvents`.
    public var events: [HostEvent]
    /// Good feed answers only (received / no data), by endpoint path.
    public var feeds: [String: RelayFeedState]
    public var fetchedAt: Date?

    public init(base: String, host: HostStatus?, events: [HostEvent], feeds: [RelayEndpoint: RelayFeedState], fetchedAt: Date?) {
        self.base = base
        self.host = host
        self.events = Array(events.prefix(Self.maxEvents))
        self.feeds = Dictionary(uniqueKeysWithValues: feeds.filter { $0.value.isGood }.map { ($0.key.rawValue, $0.value) })
        self.fetchedAt = fetchedAt
    }

    public var feedStates: [RelayEndpoint: RelayFeedState] {
        Dictionary(uniqueKeysWithValues: feeds.compactMap { key, value in RelayEndpoint(rawValue: key).map { ($0, value) } })
    }

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PortSight", isDirectory: true)
    }

    public func save(to url: URL) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public static func load(from url: URL) -> RelayCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RelayCache.self, from: data)
    }

    public static func delete(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

