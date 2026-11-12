import Foundation
import Testing
@testable import PortSightKit

/// /ibkr/status, /account's personal_ibkr, /notices, /calendar and /news, and the store they share.
struct RelayFeedsTests {
    private let base = "https://chrismac-mini.tail99a219.ts.net"

    // MARK: IBKR models

    @Test func ibkrStatusAndAccountDecodeLeniently() throws {
        let status = try JSONDecoder().decode(IBKRStatus.self, from: Data(#"{"available": true, "state": "awaiting_2fa", "since": "2026-11-11T08:00:00Z", "message": " "}"#.utf8))
        #expect(status.state == .awaiting2FA && status.state.showsBanner && status.message == nil)
        #expect(IBKRState("NEEDS_REAUTH") == .needsReauth && IBKRState("weird") == .unknown("weird"))
        #expect(!IBKRState.connected.showsBanner && !IBKRState.offline.showsBanner)

        let json = #"""
        {"available": true, "quant": {"equity": 1},
         "personal_ibkr": {"available": true, "as_of": "2026-11-11T08:00:05Z", "heartbeat_at": "2026-11-11T08:00:06Z",
           "changed_at": "2026-11-11T07:59:00Z", "source": "realtime", "stale": false, "stale_reason": "",
           "net_liquidation": "125000.5", "cash": 20000, "buying_power": 80000, "currency": "USD", "account": "****4567",
           "positions": [{"symbol": "AAPL", "con_id": 265598, "sec_type": "STK", "quantity": 10, "avg_cost": 180.5,
                          "market_value": 2250, "unrealized_pnl": 445, "daily_pnl": null, "currency": "USD"},
                         {"no_symbol": true}, null]}}
        """#
        let personal = try #require(try JSONDecoder().decode(IBKRAccountDocument.self, from: Data(json.utf8)).personal_ibkr)
        #expect(personal.netValue == 125_000.5 && personal.cash == 20_000 && personal.buyingPower == 80_000)
        #expect(personal.accountTail == "4567" && personal.stale_reason == nil && personal.changed_at == "2026-11-11T07:59:00Z")
        let aapl = try #require(personal.positions.first)
        #expect(personal.positions.count == 1 && aapl.quantity == 10 && aapl.cost == 180.5 && aapl.conID == 265598)
        #expect(aapl.secType == "STK" && aapl.dailyPnl == nil && aapl.id == "265598")
        #expect(!personal.isMarkedStale && personal.unrealizedTotal == 445 && personal.dailyTotal == nil)
        #expect(PersonalIBKR(source: "flex").isMarkedStale && PersonalIBKR(stale: true).isMarkedStale)
        // Only the fixed names are read.
        let other = try JSONDecoder().decode(PersonalIBKR.self, from: Data(#"{"nav": 1, "net_value": 2}"#.utf8))
        #expect(other.netValue == nil)

        // The saved copy round-trips.
        let again = try JSONDecoder().decode(PersonalIBKR.self, from: JSONEncoder().encode(personal))
        #expect(again == personal)
    }

    // MARK: IBKR store

    /// A store whose reads answer from `answers` (by path) and whose reauth answers `reauth`.
    @MainActor
    private final class FakeRelay {
        var answers: [String: Result<Data, Error>] = [:]
        var reads: [String] = []
        var reauth: Result<(Int, Data), Error> = .success((200, Data(#"{"accepted": true, "state": "logging_in"}"#.utf8)))
        var posts = 0

        func read(_ endpoint: RelayEndpoint, _ query: [URLQueryItem]) async throws -> Data {
            reads.append(endpoint.rawValue)
            return try (answers[endpoint.rawValue] ?? .failure(ServerError.http(404))).get()
        }

        func status(_ state: String, message: String? = nil) {
            let text = message.map { #", "message": "\#($0)""# } ?? ""
            answers["/ibkr/status"] = .success(Data(#"{"available": true, "state": "\#(state)"\#(text)}"#.utf8))
        }
    }

    @MainActor
    private func store(_ relay: FakeRelay) -> IBKRStore {
        IBKRStore(read: { try await relay.read($0, $1) }, base: { self.base }, post: {
            relay.posts += 1
            return try relay.reauth.get()
        }, usesRelay: { true }, cache: false)
    }

    @Test @MainActor func bannerFollowsTheLoginState() async {
        let relay = FakeRelay()
        let ibkr = store(relay)
        relay.status("connected")
        await ibkr.refreshStatus(force: true)
        #expect(ibkr.banner() == nil && !ibkr.bannerVisible)

        relay.status("needs_reauth")
        await ibkr.refreshStatus(force: true)
        let banner = ibkr.banner()
        #expect(banner?.title == "IBKR 需要重新授权" && banner?.detail == "点击后请在 IBKR Mobile 上确认登录")
        #expect(banner?.showsButton == true && banner?.buttonEnabled == true && ibkr.bannerVisible)

        // 重新授权 → logging_in at once, the button gone, and not sent again within two minutes.
        await ibkr.reauthorize()
        #expect(relay.posts == 1 && ibkr.state == .loggingIn && ibkr.banner()?.title == "正在登录 IBKR…")
        await ibkr.reauthorize()
        #expect(relay.posts == 1)

        relay.status("awaiting_2fa")
        await ibkr.refreshStatus(force: true)
        #expect(ibkr.banner()?.title == "请打开 IBKR Mobile 确认登录")

        // Confirmed: the banner goes, a short 已重新授权 shows.
        relay.status("connected")
        await ibkr.refreshStatus(force: true)
        #expect(ibkr.banner() == nil && ibkr.notice?.text == "IBKR 已重新授权" && ibkr.notice?.tone == .success)
    }

    @Test @MainActor func aFailedLoginShowsWhyAndAllowsAnotherTry() async {
        let relay = FakeRelay()
        let ibkr = store(relay)
        relay.status("needs_reauth")
        await ibkr.refreshStatus(force: true)
        await ibkr.reauthorize()
        relay.status("needs_reauth", message: "IB Gateway 已退出，登录没有完成")
        await ibkr.refreshStatus(force: true)
        // The reason on the banner; the button waits for the two-minute throttle, counting down.
        let banner = ibkr.banner()
        #expect(banner?.detail == "IB Gateway 已退出，登录没有完成" && banner?.buttonEnabled == false)
        #expect(banner?.cooldownText()?.hasSuffix("秒后可再次点击") == true && banner?.cooldownText()?.hasPrefix("刚刚") == false)
        await ibkr.reauthorize()
        #expect(relay.posts == 1)
        // Two minutes later it may be pressed again.
        let later = Date.now.addingTimeInterval(IBKRStore.reauthCooldown + 1)
        #expect(ibkr.banner(now: later)?.buttonEnabled == true && ibkr.banner(now: later)?.cooldownText(now: later) == nil)
        await ibkr.reauthorize(now: later)
        #expect(relay.posts == 2)
    }

    @Test @MainActor func reauthAnswersOtherThanAccepted() async {
        let relay = FakeRelay()
        let ibkr = store(relay)
        relay.status("needs_reauth")
        await ibkr.refreshStatus(force: true)

        // 429: asked moments ago. Say so and don't send again.
        relay.reauth = .success((429, Data()))
        await ibkr.reauthorize()
        let cooling = ibkr.banner()
        #expect(cooling?.buttonEnabled == false && ibkr.notice == nil)
        #expect(cooling?.cooldownText(now: .now)?.hasPrefix("刚刚已发起登录，请在 IBKR Mobile 上确认；") == true)
        #expect(cooling?.cooldownText(now: .now)?.contains("120 秒后可再次点击") == true
                || cooling?.cooldownText(now: .now)?.contains("119 秒后可再次点击") == true)
        await ibkr.reauthorize()
        #expect(relay.posts == 1)

        // 503: IBKR is not set up on the Mac mini (not a network error).
        let unset = store(relay)
        relay.status("needs_reauth")
        await unset.refreshStatus(force: true)
        relay.reauth = .success((503, Data(#"{"error": "not_configured"}"#.utf8)))
        await unset.reauthorize()
        #expect(unset.notice?.text == "服务器端 IBKR 未配置" && unset.notice?.tone == .warning)

        // 409: already connected → the status is read again.
        let other = store(relay)
        relay.status("needs_reauth")
        await other.refreshStatus(force: true)
        relay.reauth = .success((409, Data()))
        relay.status("connected")
        let before = relay.reads.count
        await other.reauthorize()
        #expect(relay.reads.count == before + 1 && other.state == .connected)

        // 404: not open yet.
        let third = store(relay)
        relay.reauth = .success((404, Data()))
        await third.reauthorize()
        #expect(third.notice?.text == "重新授权尚未开放")
    }

    /// 「非实时 · 截至 <as_of>」 when stale = true or source = "flex", and for the copy kept for offline.
    @Test @MainActor func figuresAreMarkedWhenNotLive() async {
        let relay = FakeRelay()
        let ibkr = store(relay)
        func account(stale: Bool = false, source: String = "realtime", reason: String = "") {
            relay.answers["/account"] = .success(Data(#"{"personal_ibkr": {"available": true, "as_of": "2026-11-11T08:00:05Z", "stale": \#(stale), "stale_reason": "\#(reason)", "source": "\#(source)", "net_liquidation": 1}}"#.utf8))
        }
        account()
        await ibkr.refreshAccount(force: true)
        #expect(ibkr.isLive() && ibkr.delayedNote() == nil && ibkr.staleReason == nil)

        account(stale: true, reason: "同步程序 3 分钟没有心跳")
        await ibkr.refreshAccount(force: true)
        #expect(!ibkr.isLive() && ibkr.delayedNote()?.hasPrefix("非实时 · 截至 ") == true)
        #expect(ibkr.staleReason == "同步程序 3 分钟没有心跳")

        account(source: "flex")
        await ibkr.refreshAccount(force: true)
        #expect(!ibkr.isLive())

        // Offline: the saved copy is shown, never as live.
        account()
        await ibkr.refreshAccount(force: true)
        #expect(ibkr.isLive())
        relay.answers["/account"] = .failure(URLError(.timedOut))
        await ibkr.refreshAccount(force: true)
        #expect(!ibkr.isLive() && ibkr.account.document != nil && ibkr.account.isSaved)

        // Not connected yet: the relay's message, no figures.
        relay.answers["/account"] = .success(Data(#"{"personal_ibkr": {"available": false, "message": "IBKR 尚未接入"}}"#.utf8))
        let fresh = store(relay)
        await fresh.refreshAccount(force: true)
        #expect(fresh.account.phase == .unavailable("IBKR 尚未接入") && fresh.account.document == nil)
        // The quant part not ready (top-level available false) does not hide a live personal_ibkr.
        relay.answers["/account"] = .success(Data(#"{"available": false, "personal_ibkr": {"available": true, "source": "realtime", "net_liquidation": 5}}"#.utf8))
        let quantNotReady = store(relay)
        await quantNotReady.refreshAccount(force: true)
        #expect(quantNotReady.account.phase == .loaded && quantNotReady.account.document?.netValue == 5)
        relay.answers["/account"] = .success(Data(#"{"available": true}"#.utf8))
        let missing = store(relay)
        await missing.refreshAccount(force: true)
        #expect(missing.account.phase == .unavailable("IBKR 尚未接入"))
    }

    // MARK: Shared store

    @Test @MainActor func feedStoreKeepsTheLastGoodDocument() async throws {
        var answer: Result<Data, Error> = .success(Data(#"{"available": true, "state": "connected"}"#.utf8))
        let name = "test-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(at: RelayCache.directory.appendingPathComponent(name)) }
        func make() -> RelayFeedStore<IBKRStatus> {
            RelayFeedStore(cacheName: name, minInterval: 0, read: { _, _ in try answer.get() }, base: { self.base }) { read in
                let data = try await read(.ibkrStatus, [])
                if let message = RelayAvailability.unavailableMessage(data) { return .unavailable(message) }
                return .document(try JSONDecoder().decode(IBKRStatus.self, from: data))
            }
        }
        let store = make()
        await store.load()
        #expect(store.phase == .loaded && store.document?.state == .connected && !store.isSaved)

        // Offline: the document stays, marked as saved.
        answer = .failure(URLError(.notConnectedToInternet))
        await store.load()
        #expect(store.document?.state == .connected && store.isSaved && store.phase == .failed("连不上服务器（检查网络）"))

        // After a restart it comes back from disk.
        let restarted = make()
        #expect(restarted.document?.state == .connected && restarted.isSaved && restarted.phase == .loaded)

        // Not ready / not open: nothing shown, nothing kept.
        answer = .success(Data(#"{"available": false, "message": "通知尚未接入"}"#.utf8))
        await restarted.load()
        #expect(restarted.phase == .unavailable("通知尚未接入") && restarted.document == nil)
        answer = .failure(ServerError.http(404))
        await restarted.load()
        #expect(restarted.phase == .notOpen)
        #expect(make().document == nil)
        #expect(RelayFeedStore<IBKRStatus>.Phase.notOpen.placeholder(notOpen: "相关新闻尚未开放")?.title == "相关新闻尚未开放")
    }

    /// A failed read is tried again after `retryAfterFailure`, not a whole `minInterval` later; a good one is reused.
    @Test @MainActor func aFailedReadIsRetriedSoon() async {
        var reads = 0
        var answer: Result<Data, Error> = .failure(ServerError.http(403))
        let store = RelayFeedStore<IBKRStatus>(cacheName: nil, minInterval: 300, retryAfterFailure: 0,
                                               read: { _, _ in reads += 1; return try answer.get() }, base: { self.base }) { read in
            .document(try JSONDecoder().decode(IBKRStatus.self, from: try await read(.ibkrStatus, [])))
        }
        await store.load()
        #expect(reads == 1 && store.phase == .failed("服务器暂时拒绝了这项请求（403），稍后自动再试"))
        answer = .success(Data(#"{"state": "connected"}"#.utf8))
        await store.load()
        #expect(reads == 2 && store.phase == .loaded)
        await store.load()
        #expect(reads == 2)
    }

    // MARK: Notices

    @Test func noticesDecodeAndLinksParse() throws {
        let page = #"""
        {"available": true, "events": [
          {"id": "protect:2026-11-11:a1", "category": "safety", "severity": "critical", "title": "量化保护检查触发",
           "detail": "异常报价", "at": "2026-11-11T02:34:00Z", "owner": "quant", "requires_ack": true,
           "facts": [{"label": "线路", "value": "加密"}, {"bad": 1}], "link": "report:daily:crypto:2026-11-11"},
          {"id": "ibkr:reauth:1", "category": "ops", "severity": "warning", "owner": "personal", "link": "ibkr:reauth",
           "at": "2026-11-11T03:00:00Z", "title": "IBKR 需要重新授权"},
          {"title": "no id"}],
         "next_cursor": "c2", "has_more": true}
        """#
        let decoded = try JSONDecoder().decode(RelayNoticePage.self, from: Data(page.utf8))
        #expect(decoded.events.map(\.id) == ["protect:2026-11-11:a1", "ibkr:reauth:1"])
        #expect(decoded.has_more == true && decoded.next_cursor == "c2")
        let protect = decoded.events[0]
        #expect(protect.requires_ack == true && protect.facts.count == 1 && protect.categoryTitle == "安全")
        #expect(protect.parsedLink == .lineReport(kind: "daily", line: "crypto", day: "2026-11-11"))
        #expect(decoded.events[1].isIBKRReauth && !decoded.events[1].isTrade)

        #expect(RelayLink("report:host_daily:2026-11-11") == .hostDailyReport(date: "2026-11-11"))
        #expect(RelayLink("report:weekly:stock:2026-W45")?.title == "查看周报")
        #expect(RelayLink("ibkr:reauth")?.title == "去重新授权")
        #expect(RelayLink("journal") == .journal && RelayLink("asset:aapl") == .asset(symbol: "AAPL"))
        for unknown in ["", "report:", "report:x", "ibkr:login", "https://example.com", "asset:"] {
            #expect(RelayLink(unknown) == nil, "\(unknown)")
        }

        // Newest first, one per id.
        let list = RelayNoticeList(notices: decoded.events + [decoded.events[0]])
        #expect(list.notices.map(\.id) == ["ibkr:reauth:1", "protect:2026-11-11:a1"])
    }

    @Test @MainActor func noticesShowAsTheAppsNotices() throws {
        let notice = RelayNotice(id: "n", category: "review", severity: "loud", title: "日报已生成", at: "2026-11-11T13:00:00Z",
                                 owner: "personal", requires_ack: false, link: "nowhere:else")
        let shown = notice.asNotice(now: Date(timeIntervalSince1970: 1_794_000_000))
        #expect(shown.fromRelay && shown.owner == .personal && shown.severity == "info" && shown.category == "复盘")
        #expect(shown.link == nil && !shown.needsAcknowledgement())

        var ack = RelayNotice(id: "p", severity: "critical", requires_ack: true).asNotice()
        #expect(ack.needsAcknowledgement())
        ack.expiresAt = .now.addingTimeInterval(-1)
        #expect(!ack.needsAcknowledgement())
        // Built-in critical notices still need it.
        #expect(DemoPortfolioData.notices.first { $0.severity == "critical" }?.needsAcknowledgement() == true)

        // A warning notice waiting for 确认 shows on 需要处理 in orange.
        let warning = RelayNotice(id: "w", severity: "warning", title: "IBKR 需要重新授权", requires_ack: true).asNotice()
        let items = AttentionItems.build(notices: [warning], alerts: [], read: [], host: nil)
        #expect(items.first?.tone == .warning)
    }

    @Test @MainActor func noticesAreReadPageByPage() async throws {
        var pages = [Data(#"{"events": [{"id": "a", "at": "2026-11-11T01:00:00Z"}], "has_more": true, "next_cursor": "x"}"#.utf8),
                     Data(#"{"events": [{"id": "b", "at": "2026-11-11T02:00:00Z"}], "has_more": false}"#.utf8)]
        var queries: [[URLQueryItem]] = []
        let result = try await RelayNotices.fetch({ endpoint, query in
            #expect(endpoint == .notices)
            queries.append(query)
            return pages.removeFirst()
        })
        guard case .document(let list) = result else { Issue.record("expected notices"); return }
        #expect(list.notices.map(\.id) == ["b", "a"])
        #expect(queries.first?.first?.name == "since" && queries.last == [URLQueryItem(name: "cursor", value: "x")])

        let closed = try await RelayNotices.fetch({ _, _ in Data(#"{"available": false, "message": "通知尚未接入"}"#.utf8) })
        guard case .unavailable(let message) = closed else { Issue.record("expected unavailable"); return }
        #expect(message == "通知尚未接入")
    }

    @Test @MainActor func relayAlertsShowAsTheAppsAlerts() {
        let event = HostEvent(id: "disk_low@2026-11-11T01:00:00Z", source: "host", category: "data", severity: "warning",
                              title: "磁盘快满了", at: "2026-11-11T01:00:00Z")
        let alert = event.asTerminalAlert()
        #expect(alert.category == .data && alert.severity == .warning && alert.title == "磁盘快满了" && alert.source == "host")
        #expect(HostEvent(id: "x").asTerminalAlert().category == .ops)
    }

    // MARK: Calendar and news

    @Test @MainActor func calendarAndNewsDecode() throws {
        let json = #"""
        {"available": true, "as_of": "2026-11-11T00:00:00Z", "days": 14, "earnings_available": false,
         "message": "财报日程等个人持仓数据源接入后提供；现在只有宏观事件",
         "events": [{"id": "fomc", "title": "美联储利率决议", "category": "macro", "at": "2026-12-04T19:00:00Z"},
                    {"title": "Apple 财报", "category": "earnings", "at": "2026-11-20T21:00:00Z", "session": "post", "symbols": ["AAPL"]},
                    {"category": "macro"}]}
        """#
        let calendar = try JSONDecoder().decode(RelayCalendar.self, from: Data(json.utf8))
        #expect(calendar.events.count == 2 && calendar.earnings_available == false && calendar.message?.hasPrefix("财报日程") == true)
        let apple = try #require(calendar.events.last?.asMarketEvent)
        #expect(apple.title == "Apple 财报（盘后）" && apple.category == "公司财报" && apple.symbols == ["AAPL"])
        #expect(calendar.events.first?.categoryTitle == "宏观事件")

        let news = try JSONDecoder().decode(RelayNewsList.self, from: Data(#"{"items": [{"id": "n1", "title": "AI 算力", "summary": "云厂商", "symbols": ["NVDA"], "published_at": "2026-11-11T00:00:00Z"}, {"summary": "no title"}]}"#.utf8))
        #expect(news.items.count == 1 && news.items[0].asMarketNews.symbols == ["NVDA"])
    }

    @Test func reauthIsAnAuthorizedPOST() throws {
        let request = try #require(RelayAPI.ibkrReauthRequest(base: base, deviceToken: "dev-token"))
        #expect(request.httpMethod == "POST" && request.url?.absoluteString == base + "/ibkr/reauth")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dev-token")
        #expect(request.httpBody == Data("{}".utf8) && RelayAPI.isRelayRequest(request))
        #expect(RelayAPI.ibkrReauthRequest(base: "http://mac-mini.ts.net", deviceToken: "t") == nil)
    }
}
