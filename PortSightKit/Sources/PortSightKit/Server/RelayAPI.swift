//
//  RelayAPI.swift
//  PortSight
//
//  The requests sent to the Mac mini's relay, built in one place so they can be tested without a network:
//  POST /devices (pairing with the one-time code, then push registration with the device bearer) and the
//  read-only GETs (RelayEndpoint). HTTPS only. Nothing here logs; the pairing code, device token and APNs token never leave
//  the request they belong to.
//

import Foundation

/// The relay's read endpoints. All are GET with `Authorization: Bearer <device_token>`.
public nonisolated enum RelayEndpoint: String, CaseIterable, Sendable {
    case host = "/host"
    case status = "/status"
    case alerts = "/alerts"
    case account = "/account"
    case reportsLatest = "/reports/latest"
    case advice = "/advice"
    /// G395 交易理由卡 (TradeJournal). 404 while the relay's publishing switch is off.
    case journal = "/journal"
    /// Messages for people (RelayNotices): 量化保护检查, 日报 / 周报已生成, IBKR 需要重新授权, personal trades …
    case notices = "/notices"
    /// Earnings and macro events (RelayMarket.calendar).
    case calendar = "/calendar"
    /// News about held symbols (RelayMarket.news); 404 until it opens.
    case news = "/news"
    /// Whether IB Gateway on the Mac mini is logged in to the personal IBKR account (IBKRStore).
    case ibkrStatus = "/ibkr/status"
    /// The personal IBKR account's fills, orders, position changes and cash (IBKRActivityStore): ?cursor= for what
    /// is new, ?before= for older pages.
    case ibkrActivity = "/ibkr/activity"
    /// The latest activity record number (activity_seq), read every 10 s to know when to fetch.
    case ibkrHeartbeat = "/ibkr/heartbeat"
    /// The personal IBKR account's value over a range (IBKREquityStore): ?range=1d|1w|1m|ytd|1y|all, ETag / 304.
    case ibkrEquity = "/ibkr/equity"
}

/// What the settings page shows for the relay.
public nonisolated enum RelayPairingState: Equatable, Sendable {
    case unpaired, paired, pushDelivered, needsRepair

    public var title: String {
        switch self {
        case .unpaired: "未配对"
        case .paired: "已配对"
        case .pushDelivered: "令牌已交给服务器"
        case .needsRepair: "需要重新配对"
        }
    }
}

/// Push switch and the device's APNs token (lowercase hex), shared by the iOS and Mac apps.
/// The token is not a secret credential (it only addresses this device); the relay's device token is, and stays
/// in the keychain.
public nonisolated enum ServerPushSettings {
    public static let enabledKey = "server.pushEnabled"
    public static let tokenKey = "server.pushToken"
    /// The relay origin that acknowledged this device's current APNs token.
    static let deliveredKey = "server.pushDeliveredTo"

    public static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    public static var token: String? {
        get { UserDefaults.standard.string(forKey: tokenKey).flatMap { $0.isEmpty ? nil : $0 } }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }

    static var deliveredTo: String? {
        get { UserDefaults.standard.string(forKey: deliveredKey) }
        set { UserDefaults.standard.set(newValue, forKey: deliveredKey) }
    }
}

public nonisolated enum RelayAPI {
    /// The daily digest time sent with every POST /devices (21:00).
    public static let digestHour = 21
    public static let digestMinute = 0

    /// URLProtocol property that marks a relay request, so the Mac's offline guard (DemoOfflineProtocol) lets
    /// exactly these through while the rest of the app stays offline.
    static let relayMarker = "PortSight.relayRequest"

    /// APNs device token as lowercase hex.
    public static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    /// POST /devices with the one-time pairing code (5 minutes, single use). No bearer yet.
    public static func pairingRequest(base: String, code: String, apnsToken: String) -> URLRequest? {
        devicesRequest(base: base, bearer: nil,
                       body: ["pairing_code": code, "apns_token": apnsToken,
                              "digest_hour": digestHour, "digest_minute": digestMinute])
    }

    /// POST /devices with the device bearer: stores this device's APNs token; "" stops pushes to it.
    public static func registerRequest(base: String, deviceToken: String, apnsToken: String) -> URLRequest? {
        devicesRequest(base: base, bearer: deviceToken,
                       body: ["apns_token": apnsToken, "digest_hour": digestHour, "digest_minute": digestMinute])
    }

    /// GET <endpoint> with the device bearer.
    public static func readRequest(base: String, endpoint: RelayEndpoint, deviceToken: String,
                                   query: [URLQueryItem] = []) -> URLRequest? {
        guard var parts = URLComponents(string: base + endpoint.rawValue), parts.scheme == "https" else { return nil }
        parts.queryItems = query.isEmpty ? nil : query
        guard let url = parts.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        return marked(request)
    }

    /// `{"device_token": "..."}` from a successful pairing.
    public static func deviceToken(from data: Data) -> String? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = body["device_token"] as? String, !token.isEmpty else { return nil }
        return token
    }

    /// `{"registered": true}` from a push registration.
    public static func isRegistered(_ data: Data) -> Bool {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return body["registered"] as? Bool == true
    }

    /// Why pairing failed, by HTTP status.
    public static func pairingFailure(status: Int) -> String {
        switch status {
        case 401: "配对码已过期或无效：配对码 5 分钟内有效，只能用一次。请在 Mac mini 上重新生成。"
        case 400: "请求格式不对（400），服务器没有接受。"
        default: "配对失败：服务器返回 \(status)。"
        }
    }

    /// Automatic refreshes come at least this far apart. The page on screen refreshes every 10 s while the app is in
    /// front; hidden tabs and pages, and the app in the background, do not refresh at all (the relay allows 120
    /// requests a minute per source, shared by every device on the same network).
    public static let minRefreshInterval: TimeInterval = 10

    /// The endpoints with no page yet (RelayEndpoint.pending) are only checked for `available` / `as_of`: at most
    /// once a minute, not with every 10 s refresh.
    public static let pendingFeedsInterval: TimeInterval = 60

    /// The shortest wait after a 429 (the relay allows 120 requests a minute per source).
    public static let rateLimitWait: TimeInterval = 30
    /// The wait after a 403: that endpoint (or a refused pairing) is not asked again for 10 minutes. (Only 401s
    /// count towards the relay's lockout: more than 10 in 10 minutes lock the source for 10 minutes.)
    public static let lockoutWait: TimeInterval = 10 * 60

    /// How long to send nothing after this answer: 429 → Retry-After (seconds), at least 30 s; 403 → 10 minutes;
    /// anything else → nil.
    public static func backoff(status: Int, retryAfter: String?) -> TimeInterval? {
        switch status {
        case 429:
            let asked = retryAfter.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? 0
            return max(asked.isFinite ? asked : 0, rateLimitWait)
        case 403:
            return lockoutWait
        default:
            return nil
        }
    }

    /// True for a request built here (see relayMarker).
    /// The read was called off on this side (the page went away, a pull-to-refresh ended): not a failure of the
    /// server or the network, so nothing on screen changes and the next read goes ahead.
    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    public static func isRelayRequest(_ request: URLRequest) -> Bool {
        URLProtocol.property(forKey: relayMarker, in: request) != nil
    }

    /// POST /ibkr/reauth with the device bearer and an empty body: asks the Mac mini to start the IBKR login (the user
    /// confirms in IBKR Mobile). The only action the app sends besides pairing; it cannot do anything else.
    public static func ibkrReauthRequest(base: String, deviceToken: String) -> URLRequest? {
        guard let url = URL(string: base + "/ibkr/reauth"), url.scheme == "https" else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)
        return marked(request)
    }

    private static func devicesRequest(base: String, bearer: String?, body: [String: Any]) -> URLRequest? {
        guard let url = URL(string: base + "/devices"), url.scheme == "https",
              let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = data
        return marked(request)
    }

    private static func marked(_ request: URLRequest) -> URLRequest {
        guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else { return request }
        URLProtocol.setProperty(true, forKey: relayMarker, in: mutable)
        return mutable as URLRequest
    }
}

extension RelayEndpoint {
    /// The four reads with no page yet (/host and /alerts have theirs). Their full fields come later.
    public static let pending: [RelayEndpoint] = [.status, .account, .reportsLatest, .advice]

    public var title: String {
        switch self {
        case .host: "主机状态"
        case .status: "量化状态"
        case .alerts: "告警"
        case .account: "账户"
        case .reportsLatest: "最新报告"
        case .advice: "建议"
        case .journal: "交易理由"
        case .notices: "通知"
        case .calendar: "日历"
        case .news: "新闻"
        case .ibkrStatus: "IBKR 授权状态"
        case .ibkrActivity: "IBKR 交易与资金记录"
        case .ibkrHeartbeat: "IBKR 记录更新"
        case .ibkrEquity: "IBKR 账户走势"
        }
    }
}

/// What every relay document shares. All fields are optional, unknown fields are ignored, and a body that is not
/// a JSON object still decodes (to all nil), so a newer or older relay never breaks the app.
public nonisolated struct RelayDocument: Decodable, Equatable, Sendable {
    public var available: Bool?
    public var message: String?
    public var as_of: String?
    public var generated_at: String?

    private enum CodingKeys: String, CodingKey { case available, message, as_of, generated_at }

    public init(available: Bool? = nil, message: String? = nil, as_of: String? = nil, generated_at: String? = nil) {
        self.available = available
        self.message = message
        self.as_of = as_of
        self.generated_at = generated_at
    }

    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        available = try? c.decodeIfPresent(Bool.self, forKey: .available)
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        as_of = try? c.decodeIfPresent(String.self, forKey: .as_of)
        generated_at = try? c.decodeIfPresent(String.self, forKey: .generated_at)
    }
}

/// One pending endpoint's last read, for the 服务器 page.
public nonisolated enum RelayFeedState: Equatable, Sendable, Codable {
    /// `available: false`: the quant system has not filled this endpoint yet.
    case noData
    /// Answered with data; the page for it comes once its fields are settled.
    case received(asOf: String?)
    case needsRepair
    case failed(String)

    /// An answer worth keeping when a later read fails.
    public var isGood: Bool {
        switch self {
        case .noData, .received: true
        case .needsRepair, .failed: false
        }
    }

    public init(_ document: RelayDocument) {
        self = document.available == false ? .noData : .received(asOf: document.as_of ?? document.generated_at)
    }

    public var title: String {
        switch self {
        case .noData: "暂无数据"
        case .received: "已有数据"
        case .needsRepair: "需要重新配对"
        case .failed: "读取失败"
        }
    }
}

/// Why the relay could not be read, for the banners.
public nonisolated enum RelayFailure: Equatable, Sendable {
    /// No answer: offline, timed out, DNS, TLS.
    case network
    /// 429: the server asked this device to slow down.
    case rateLimited
    /// 403: the server refused the request; asked again in 10 minutes.
    case locked
    /// 401: pair again.
    case unauthorized
    /// Any other HTTP status, or a reply that is not what the app expects.
    case server(Int?)

    public init(_ error: Error) {
        switch error {
        case ServerError.rateLimited: self = .rateLimited
        case ServerError.http(403): self = .locked
        case ServerError.unauthorized: self = .unauthorized
        case ServerError.http(let status): self = .server(status)
        case ServerError.invalidResponse, is DecodingError: self = .server(nil)
        default: self = .network
        }
    }

    /// The refresh message under the server page.
    public var message: String {
        switch self {
        case .network: "连不上服务器：检查网络。下面是上次保存的数据。"
        case .rateLimited: "请求太频繁，服务器让这台设备稍后再试，会自动重试。下面是上次保存的数据。"
        case .locked: "服务器拒绝了这台设备的请求（403），10 分钟后自动重试。下面是上次保存的数据。"
        case .unauthorized: "需要重新配对：服务器不再认这台设备的凭证。到设置里重新输入配对码。"
        case .server(let status): "服务器出错" + (status.map { "（\($0)）" } ?? "") + "，下面是上次保存的数据。"
        }
    }
}

/// The connection banner over the server page (and the Mac menu bar's line), the same on iOS and Mac. Pairing
/// problems (未配对, 需要重新配对) are shown by the pages themselves before this.
public nonisolated struct RelayConnectionBanner: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case offline, rateLimited, serverError, stale }

    public let kind: Kind
    public let title: String
    public let detail: String

    /// - Parameters:
    ///   - failure: why the last refresh failed, nil after a good one.
    ///   - networkHint: "手机网络" on iOS, "网络" on the Mac.
    ///   - savedAt: when the data on screen was read (nil: nothing read yet).
    ///   - freshness: the /host heartbeat's age.
    ///   - reachedServer: a refresh got through since launch, so a stale heartbeat means the server is up but the
    ///     Mac mini's status job is not writing.
    public static func make(failure: RelayFailure?, networkHint: String, savedAt: Date?, hasData: Bool,
                            freshness: ServerFreshness, staleAfterMinutes: Double, blockedUntil: Date?,
                            reachedServer: Bool) -> RelayConnectionBanner? {
        let saved = hasData ? "显示的是" + (savedAt.map { " \(ServerDates.clock($0)) " } ?? "上次") + "保存的数据。"
                            : "已配对，还没读到数据。"
        switch failure {
        case .network?:
            return .init(kind: .offline, title: "连不上服务器（检查\(networkHint)）", detail: saved)
        case .rateLimited?:
            let when = blockedUntil.map { "，\(ServerDates.clock($0)) 后自动重试" } ?? "，稍后自动重试"
            return .init(kind: .rateLimited, title: "请求太频繁，稍后自动再试",
                         detail: "服务器让这台设备暂停请求" + when + "。" + saved)
        case .locked?:
            let when = blockedUntil.map { "，\(ServerDates.clock($0)) 后自动重试" } ?? "，10 分钟后自动重试"
            return .init(kind: .rateLimited, title: "服务器拒绝了请求（403）",
                         detail: "主机状态暂时读不到" + when + "。" + saved)
        case .server(let status)?:
            return .init(kind: .serverError, title: "服务器出错" + (status.map { "（\($0)）" } ?? ""), detail: saved)
        case .unauthorized?, nil:
            break
        }
        guard freshness.state == .stale else { return nil }
        let beat = "最后心跳 \(ServerDates.clock(freshness.lastBeat))（\(ServerDates.age(minutes: freshness.ageMinutes))）"
        let minutes = Int(staleAfterMinutes)
        if reachedServer {
            return .init(kind: .stale, title: "服务器在线，但 Mac mini 的状态超过 \(minutes) 分钟没更新",
                         detail: beat + "：Mac mini 上的主机状态任务可能停了。")
        }
        return .init(kind: .stale, title: "Mac mini 的状态超过 \(minutes) 分钟没更新", detail: beat + "，正在连接服务器。")
    }
}
