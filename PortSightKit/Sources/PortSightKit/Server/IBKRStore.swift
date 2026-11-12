//
//  IBKRStore.swift
//  PortSightKit
//
//  The personal IBKR account for the pages: GET /ibkr/status (is IB Gateway on the Mac mini logged in?) and the
//  `personal_ibkr` part of GET /account. IBKR wants a two-factor login every week: the home page's banner then
//  offers 重新授权, which only asks the Mac mini to start the login (POST /ibkr/reauth, the one action the app sends);
//  the user confirms in IBKR Mobile. The banner is about that state alone, never about a notice's 确认已查看: only
//  state = connected ends it.
//
//  Reading cadence (the relay limits each source to 120 requests a minute):
//  - /ibkr/status: once when the app opens or comes back, every 6 s while the banner shows, else with /account.
//  - /account: every 10 s while the 资产 page is on screen and the app is in front, at once after a trade notice.
//  - 429: the whole relay pauses at least 30 s (ServerStore); a 429 on the reauth itself means "asked moments ago".
//
//  Figures are live only while the server says so (not stale, not the daily flex statement) and they were just read
//  (not the copy saved for offline); otherwise they are marked 「非实时 · 截至 <as_of>」. The last account read stays on screen offline and after a
//  restart, and is deleted when the relay is unpaired.
//

import Foundation
import Observation

@Observable
public final class IBKRStore {
    public static let shared = IBKRStore()

    /// POST /ibkr/reauth: the HTTP status and body (ServerStore.postIBKRReauth; replaced in tests).
    public typealias Poster = () async throws -> (status: Int, body: Data)

    public static let bannerInterval: TimeInterval = 6
    public static let accountInterval: TimeInterval = 10
    /// A reauth answered 200 or 429 is not sent again for this long.
    public static let reauthCooldown: TimeInterval = 120

    public let status: RelayFeedStore<IBKRStatus>
    public let account: RelayFeedStore<PersonalIBKR>

    /// When `as_of` last changed, on this device's clock (informational; liveness follows stale / source).
    public private(set) var asOfChangedAt: Date?
    public private(set) var reauthInFlight = false
    public private(set) var cooldownUntil: Date?
    /// A short message under the banner or in its place ("IBKR 已重新授权", "刚刚已发起…").
    public private(set) var notice: IBKRNotice?

    @ObservationIgnored private let post: Poster
    @ObservationIgnored private var lastAsOf: String?
    @ObservationIgnored private var lastState: IBKRState?
    @ObservationIgnored private let usesRelay: () -> Bool

    public init(read: RelayFeedStore<IBKRStatus>.Reader? = nil, base: (() -> String?)? = nil, post: Poster? = nil,
                usesRelay: (() -> Bool)? = nil, cache: Bool = true) {
        status = RelayFeedStore(cacheName: nil, minInterval: 4, read: read, base: base) { read in
            let data = try await read(.ibkrStatus, [])
            if let message = RelayAvailability.unavailableMessage(data) { return .unavailable(message) }
            return .document(try JSONDecoder().decode(IBKRStatus.self, from: data))
        }
        account = RelayFeedStore(cacheName: cache ? "ibkr_account.json" : nil, minInterval: 5, read: read, base: base) { read in
            let data = try await read(.account, [])
            // The document's own `available` is about the quant account; personal_ibkr says for itself.
            guard let personal = try JSONDecoder().decode(IBKRAccountDocument.self, from: data).personal_ibkr else {
                return .unavailable("IBKR 尚未接入")
            }
            if personal.available == false { return .unavailable(personal.message ?? "IBKR 尚未接入") }
            return .document(personal)
        }
        self.post = post ?? { try await ServerStore.shared.postIBKRReauth() }
        self.usesRelay = usesRelay ?? { RelayNotices.usesRelay }
        lastAsOf = account.document?.as_of
    }

    public var state: IBKRState? { status.document?.state }

    // MARK: Reading

    public func refreshStatus(force: Bool = false) async {
        guard usesRelay() else { return }
        await status.load(force: force)
        let now = state
        if let previous = lastState, previous != now {
            if now == .connected, previous.showsBanner {
                notice = IBKRNotice(text: "IBKR 已重新授权", tone: .success, until: .now.addingTimeInterval(5))
                cooldownUntil = nil
            }
            // A login that failed (back to needs_reauth) keeps the two-minute throttle: the banner shows the reason
            // (the status message) and the button comes back when the countdown ends.
        }
        lastState = now
    }

    public func refreshAccount(force: Bool = false) async {
        guard usesRelay() else { return }
        let before = account.readAt
        await account.load(force: force)
        guard account.readAt != before, !account.isSaved, let document = account.document else { return }
        if document.as_of != lastAsOf { asOfChangedAt = .now }
        lastAsOf = document.as_of
    }

    /// A trade notice or a push arrived: read the account (and the status) now, not at the next tick.
    public func nudge() async {
        await refreshAccount(force: true)
        await refreshStatus(force: true)
        // 「<代码> 有新成交」/「委托有更新」: fetch what is new now (GET ?cursor=).
        await IBKRActivityStore.shared.refresh(force: true)
    }

    /// The home page: the status now, then every 6 s while the banner is up. Restart it (task id) when the banner
    /// appears, the app comes back to the front, or the pairing changes.
    public func runBannerPolling() async {
        await refreshStatus(force: true)
        while !Task.isCancelled, state?.showsBanner == true {
            try? await Task.sleep(for: .seconds(Self.bannerInterval))
            guard !Task.isCancelled else { return }
            await refreshStatus(force: true)
        }
    }

    /// The 资产 page while on screen and the app is in front: the account and the status every 10 s.
    public func runAssetsPolling() async {
        while !Task.isCancelled {
            await refreshAccount(force: true)
            await refreshStatus()
            try? await Task.sleep(for: .seconds(Self.accountInterval))
        }
    }

    // MARK: Re-authorizing

    /// 重新授权: asks the Mac mini to start the IBKR login. Nothing else can be asked of it.
    public func reauthorize(now: Date = .now) async {
        guard !reauthInFlight else { return }
        // A login started (or refused as too soon) under two minutes ago: don't ask again (the banner counts down).
        if let cooldownUntil, cooldownUntil > now { return }
        reauthInFlight = true
        defer { reauthInFlight = false }
        do {
            let (code, body) = try await post()
            switch code {
            case 200..<300:
                let answered = (try? JSONDecoder().decode(IBKRStatus.self, from: body))?.state
                let next: IBKRState = if case .unknown = answered ?? .unknown("") { .loggingIn } else { answered ?? .loggingIn }
                status.show(IBKRStatus(state: next))
                lastState = next
                startCooldown(from: now)
                notice = nil
            case 409:
                // Already connected.
                await refreshStatus(force: true)
            case 429:
                // Started under two minutes ago: the banner says so and counts the two minutes down.
                startCooldown(from: now)
                notice = nil
            case 503:
                // not_configured: the Mac mini has no IBKR login set up (not a network problem).
                notice = IBKRNotice(text: "服务器端 IBKR 未配置", tone: .warning, until: now.addingTimeInterval(10))
            case 404:
                notice = IBKRNotice(text: "重新授权尚未开放", tone: .warning, until: now.addingTimeInterval(6))
            default:
                notice = IBKRNotice(text: "没能发起重新授权：服务器返回 \(code)", tone: .warning, until: now.addingTimeInterval(8))
            }
        } catch ServerError.unauthorized {
            notice = IBKRNotice(text: "需要重新配对服务器", tone: .warning, until: now.addingTimeInterval(8))
        } catch ServerError.rateLimited {
            notice = IBKRNotice(text: "请求太频繁，稍后再试", tone: .warning, until: now.addingTimeInterval(8))
        } catch {
            notice = IBKRNotice(text: "连不上服务器（检查网络）", tone: .warning, until: now.addingTimeInterval(8))
        }
    }

    public func dismissNotice() { notice = nil }

    /// Two minutes without another reauth; cleared when they are over, so the banner's button comes back by itself
    /// (nothing else would redraw it while the status stays the same).
    private func startCooldown(from now: Date) {
        let until = now.addingTimeInterval(Self.reauthCooldown)
        cooldownUntil = until
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
            guard let self, self.cooldownUntil == until else { return }
            self.cooldownUntil = nil
        }
    }

    /// Unpaired or another relay: forget the account and the status.
    public func reset() {
        status.reset()
        account.reset()
        asOfChangedAt = nil
        lastAsOf = nil
        lastState = nil
        cooldownUntil = nil
        notice = nil
    }

    // MARK: What the pages show

    /// The home page's banner; nil when nothing is asked of the user.
    public func banner(now: Date = .now) -> IBKRBanner? {
        guard usesRelay(), let state else { return nil }
        switch state {
        case .needsReauth:
            let cooling = (cooldownUntil ?? .distantPast) > now
            let message = status.document?.message
            return IBKRBanner(state: state, title: "IBKR 需要重新授权",
                              detail: message ?? "点击后请在 IBKR Mobile 上确认登录",
                              tone: .action, showsButton: true, buttonEnabled: !reauthInFlight && !cooling,
                              cooldownUntil: cooling ? cooldownUntil : nil, loginFailed: message != nil)
        case .loggingIn:
            return IBKRBanner(state: state, title: "正在登录 IBKR…", detail: "Mac mini 正在登录，稍后请在 IBKR Mobile 上确认",
                              tone: .progress, showsButton: false, buttonEnabled: false)
        case .awaiting2FA:
            return IBKRBanner(state: state, title: "请打开 IBKR Mobile 确认登录", detail: "确认后这里会自动更新",
                              tone: .progress, showsButton: false, buttonEnabled: false)
        default:
            return nil
        }
    }

    /// The banner should be up (drives the home page's polling task id).
    public var bannerVisible: Bool { usesRelay() && state?.showsBanner == true }

    /// The account figures may be called live: read moments ago (not a saved copy, not left over from before the
    /// page was last on screen), not stale, not from flex. The pages re-evaluate this every few seconds.
    public func isLive(now: Date = .now) -> Bool {
        guard let document = account.document, !account.isSaved, let readAt = account.readAt,
              now.timeIntervalSince(readAt) <= Self.freshFor else { return false }
        // A gateway that is logged out or down cannot be giving live figures, whatever the document says.
        if let state, state != .connected, !(state == .unknown("")) { return false }
        return !document.isMarkedStale
    }

    /// A read older than this is not called live (the 资产 page reads every 10 s while on screen).
    public static let freshFor: TimeInterval = 30

    /// The server's reason the figures are stale (stale_reason), shown under 「非实时」.
    public var staleReason: String? { account.document?.stale == true ? account.document?.stale_reason : nil }

    /// 「非实时 · 截至 11-11 14:20:05」 next to the figures, or nil while they are live.
    public func delayedNote(now: Date = .now) -> String? {
        guard let document = account.document, !isLive(now: now) else { return nil }
        guard let ms = document.asOfMs else { return "非实时" }
        return "非实时 · 截至 " + Self.asOfText(Date(timeIntervalSince1970: ms / 1_000), now: now)
    }

    /// What the account section says about the gateway when it is not simply connected.
    public var gatewayNote: String? {
        switch state {
        case .offline?: "Mac mini 上的 IB Gateway 掉线了，资产不是实时的。"
        case .notConfigured?: "Mac mini 上的 IBKR 还没配置好。"
        case .needsReauth?, .loggingIn?, .awaiting2FA?: "IBKR 需要重新授权，资产暂时不更新。"
        default: nil
        }
    }

    static func asOfText(_ date: Date, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDate(date, inSameDayAs: now) ? "HH:mm:ss" : "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

public nonisolated struct IBKRBanner: Equatable, Sendable {
    public enum Tone: Equatable, Sendable {
        /// Something to do: 重新授权.
        case action
        /// Waiting for the Mac mini or for IBKR Mobile.
        case progress
    }

    public let state: IBKRState
    public let title: String
    public let detail: String
    public let tone: Tone
    public let showsButton: Bool
    public let buttonEnabled: Bool
    /// The button is held back until then (two minutes after a login was started or refused as too soon).
    public var cooldownUntil: Date? = nil
    /// The status carries the reason the last login did not complete (shown as the detail).
    public var loginFailed: Bool = false
    public var buttonTitle: String { "重新授权" }

    public init(state: IBKRState, title: String, detail: String, tone: Tone, showsButton: Bool, buttonEnabled: Bool,
                cooldownUntil: Date? = nil, loginFailed: Bool = false) {
        self.state = state
        self.title = title
        self.detail = detail
        self.tone = tone
        self.showsButton = showsButton
        self.buttonEnabled = buttonEnabled
        self.cooldownUntil = cooldownUntil
        self.loginFailed = loginFailed
    }

    /// While the button is held back: 「刚刚已发起登录，请在 IBKR Mobile 上确认；X 秒后可再次点击」 (after a failed login, only
    /// 「X 秒后可再次点击」, the reason being the detail). Nil once the button may be pressed. Pages redraw it every second.
    public func cooldownText(now: Date = .now) -> String? {
        guard let cooldownUntil else { return nil }
        let seconds = Int(cooldownUntil.timeIntervalSince(now).rounded(.up))
        guard seconds > 0 else { return nil }
        let wait = "\(seconds) 秒后可再次点击"
        return loginFailed ? wait : "刚刚已发起登录，请在 IBKR Mobile 上确认；" + wait
    }

    /// The button may be pressed at `now` (the countdown is over).
    public func buttonEnabled(now: Date) -> Bool { buttonEnabled || (cooldownUntil.map { $0 <= now } ?? false) }
}

public nonisolated struct IBKRNotice: Equatable, Sendable {
    public enum Tone: Equatable, Sendable { case success, info, warning }
    public let text: String
    public let tone: Tone
    /// Hide it after this.
    public let until: Date

    public func isShown(now: Date = .now) -> Bool { until > now }
}

/// Money in the account's currency: "12,345.67".
public nonisolated enum IBKRFormat {
    public static func money(_ value: Double?, digits: Int = 2) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "en_US")))
    }

    public static func signedMoney(_ value: Double?, digits: Int = 2) -> String {
        guard let value, value.isFinite else { return "—" }
        return (value >= 0 ? "+" : "−") + money(abs(value), digits: digits)
    }

    public static func quantity(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...4)).locale(Locale(identifier: "en_US")))
    }
}
