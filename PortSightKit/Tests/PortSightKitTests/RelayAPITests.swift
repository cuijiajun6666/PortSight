import Foundation
import Testing
@testable import PortSightKit

struct RelayAPITests {
    /// {"available": false} from /host is "no data yet": the pages say so instead of showing empty values, and the
    /// storage pages get no volumes.
    @Test func hostWithoutDataIsNotShownAsValues() throws {
        let empty = try JSONDecoder().decode(HostStatus.self, from: Data(#"{"available": false, "message": "主机状态还没生成"}"#.utf8))
        #expect(!empty.hasData && empty.message == "主机状态还没生成")
        let sample = try JSONDecoder().decode(HostStatus.self, from: Data(ServerSample.json.utf8))
        #expect(sample.hasData)
        #expect(StorageVolume.volumes(from: sample).map(\.key) == ["internal", "main", "backup", "photos"])
    }

    /// host.thermal.cpu_temp_c / gpu_temp_c may be null (macmon not read): shown as "—". Under 85 °C is normal,
    /// 85–95 °C warm, over 95 °C hot; a non-empty thermal_warning means macOS is already throttling.
    @Test func hostTemperatures() throws {
        let json = #"{"available": true, "host": {"thermal": {"cpu_temp_c": 88.4, "gpu_temp_c": null, "thermal_warning": "2"}}}"#
        let thermal = try #require(try JSONDecoder().decode(HostStatus.self, from: Data(json.utf8)).host?.thermal)
        #expect(thermal.cpu_temp_c == 88.4 && thermal.gpu_temp_c == nil)
        #expect(HostThermal.text(thermal.cpu_temp_c) == "88.4°C" && HostThermal.text(thermal.gpu_temp_c) == "—")
        #expect(thermal.cpuLevel == .warm && thermal.gpuLevel == nil && thermal.hottest == .warm)
        #expect(thermal.overheated)

        #expect(HostThermal.level(84.9) == .normal)
        #expect(HostThermal.level(85.0) == .warm)
        #expect(HostThermal.level(95.0) == .warm)
        #expect(HostThermal.level(95.1) == .hot)
        #expect(HostThermal(cpu_temp_c: 60, gpu_temp_c: 97).hottest == .hot)
        #expect(HostThermal().hottest == nil)
        let both = HostThermal(cpu_temp_c: 88.4, gpu_temp_c: 96.2).warmReadings
        #expect(both.map(\.name) == ["GPU", "CPU"] && both.map(\.level.word) == ["过高", "偏高"])
        #expect(HostThermal(cpu_temp_c: 84.9, gpu_temp_c: nil).warmReadings.isEmpty)
        for warning in [nil, "", "  "] { #expect(!HostThermal(thermal_warning: warning).overheated) }

        let sample = try #require(ServerSample.host?.host?.thermal)
        #expect(sample.cpu_temp_c == 52.5 && sample.gpu_temp_c == 47.8 && sample.hottest == .normal && !sample.overheated)
    }

    private let base = "https://chrismac-mini.tail99a219.ts.net"

    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func pairingPostsTheCodeWithoutABearer() throws {
        let request = try #require(RelayAPI.pairingRequest(base: base, code: "482913", apnsToken: ""))
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == base + "/devices")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let json = try body(request)
        #expect(json["pairing_code"] as? String == "482913")
        #expect(json["apns_token"] as? String == "")
        #expect(json["digest_hour"] as? Int == 21 && json["digest_minute"] as? Int == 0)
        #expect(json.count == 4)
    }

    @Test func pushRegistrationCarriesTheBearerAndNoCode() throws {
        let request = try #require(RelayAPI.registerRequest(base: base, deviceToken: "dev-token", apnsToken: "00ab10ff"))
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == base + "/devices")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dev-token")
        let json = try body(request)
        #expect(json["apns_token"] as? String == "00ab10ff")
        #expect(json["digest_hour"] as? Int == 21 && json["digest_minute"] as? Int == 0)
        #expect(json["pairing_code"] == nil && json.count == 3)
        // Turning pushes off sends an empty token.
        let off = try #require(RelayAPI.registerRequest(base: base, deviceToken: "dev-token", apnsToken: ""))
        #expect(try body(off)["apns_token"] as? String == "")
    }

    @Test func everyReadIsAnAuthorizedGET() throws {
        let paths = RelayEndpoint.allCases.map(\.rawValue)
        #expect(paths == ["/host", "/status", "/alerts", "/account", "/reports/latest", "/advice", "/journal", "/notices",
                          "/calendar", "/news", "/ibkr/status", "/ibkr/activity", "/ibkr/heartbeat", "/ibkr/equity"])
        for endpoint in RelayEndpoint.allCases {
            let request = try #require(RelayAPI.readRequest(base: base, endpoint: endpoint, deviceToken: "dev-token"))
            #expect(request.httpMethod == "GET" && request.httpBody == nil)
            #expect(request.url?.absoluteString == base + endpoint.rawValue)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dev-token")
        }
        let since = try #require(RelayAPI.readRequest(base: base, endpoint: .alerts, deviceToken: "t",
                                                      query: [URLQueryItem(name: "since", value: "2026-11-02T00:00:00Z")]))
        #expect(since.url?.query == "since=2026-11-02T00:00:00Z")
    }

    @Test func plainHTTPIsNeverBuilt() {
        #expect(RelayAPI.pairingRequest(base: "http://mac-mini.ts.net", code: "1", apnsToken: "") == nil)
        #expect(RelayAPI.registerRequest(base: "http://mac-mini.ts.net", deviceToken: "t", apnsToken: "") == nil)
        #expect(RelayAPI.readRequest(base: "http://mac-mini.ts.net", endpoint: .host, deviceToken: "t") == nil)
    }

    @Test func readsTheRelayReplies() {
        #expect(RelayAPI.deviceToken(from: Data(#"{"device_token": "abc"}"#.utf8)) == "abc")
        #expect(RelayAPI.deviceToken(from: Data(#"{"device_token": ""}"#.utf8)) == nil)
        #expect(RelayAPI.deviceToken(from: Data("not json".utf8)) == nil)
        #expect(RelayAPI.isRegistered(Data(#"{"registered": true}"#.utf8)))
        #expect(!RelayAPI.isRegistered(Data(#"{"registered": false}"#.utf8)))
    }

    @Test func pairingFailuresSayWhy() {
        #expect(RelayAPI.pairingFailure(status: 401).contains("过期或无效"))
        #expect(RelayAPI.pairingFailure(status: 400).contains("格式"))
        #expect(RelayAPI.pairingFailure(status: 500).contains("500"))
    }

    @Test func apnsTokenIsLowercaseHex() {
        #expect(RelayAPI.hex(Data([0x00, 0xAB, 0x10, 0xFF])) == "00ab10ff")
    }

    @Test func pairingStateTitles() {
        #expect(RelayPairingState.unpaired.title == "未配对")
        #expect(RelayPairingState.paired.title == "已配对")
        #expect(RelayPairingState.pushDelivered.title == "令牌已交给服务器")
        #expect(RelayPairingState.needsRepair.title == "需要重新配对")
    }

    @Test func pendingDocumentsDecodeWithEveryFieldOptional() throws {
        let decode = { (json: String) in try JSONDecoder().decode(RelayDocument.self, from: Data(json.utf8)) }
        let empty = try decode(#"{"available": false, "message": "量化系统还没有写入"}"#)
        #expect(empty.available == false && RelayFeedState(empty) == .noData && RelayFeedState(empty).title == "暂无数据")
        let filled = try decode(#"{"as_of": "2026-11-09T04:00:00Z", "lines": [{"id": 1}], "new_field": null}"#)
        #expect(filled.available == nil && RelayFeedState(filled) == .received(asOf: "2026-11-09T04:00:00Z"))
        // Wrong types and non-object bodies still decode, to nil fields.
        let odd = try decode(#"{"available": "no", "as_of": 5}"#)
        #expect(odd.available == nil && odd.as_of == nil)
        #expect(try decode("[1, 2]") == RelayDocument())
        #expect(RelayEndpoint.pending == [.status, .account, .reportsLatest, .advice])
    }
}

struct RelayPushEventTests {
    /// Same kind: the part before "@"; host alerts put their time last after ":"; anything else is its own kind.
    @Test func eventKindsGroupOccurrences() {
        #expect(PushEventRef.kind(of: "forward_lockbox_audit@2026-11-09T12:00Z") == "forward_lockbox_audit")
        #expect(PushEventRef.kind(of: "host:hb:forward15m:20261103T014000Z") == "host:hb:forward15m")
        #expect(PushEventRef.kind(of: "host:hb:forward15m:20261104T020000Z") == "host:hb:forward15m")
        #expect(PushEventRef.kind(of: "host:hb:forward15m:20261103T014000Z:critical") == "host:hb:forward15m")
        #expect(PushEventRef.kind(of: "host:hb:forward15m:20261103T014000Z:recovered") == "host:hb:forward15m")
        #expect(PushEventRef.kind(of: "host:hb:forward15m:20261103T014000Z:critical:recovered") == "host:hb:forward15m")
        #expect(PushEventRef.kind(of: "relay:crypto:stop") == "relay:crypto:stop")
        #expect(PushEventRef.kind(of: "relay:critical") == "relay:critical")
        #expect(PushEventRef.kind(of: "plain") == "plain")
    }

    /// The page's fallback note says why it shows the push text: no event, not paired, or not on the relay.
    @Test func lookupSaysWhyAnEventIsMissing() async {
        UserDefaults.standard.removeObject(forKey: ServerStore.urlKey)
        let store = ServerStore()                                   // unpaired: the sample host and its alerts
        let digest = PushEventRef(eventID: nil, title: "每日摘要", body: "…")
        let known = PushEventRef(eventID: "host:hb:forward15m:20261103T014000Z", title: "警告：心跳", body: "…")
        let unknown = PushEventRef(eventID: "nothing@2026-11-10T00:00Z", title: "严重：x", body: "…")

        let none = await store.lookUpEvent(digest)
        #expect(none.event == nil && none.fallbackNote == nil)
        #expect(await store.lookUpEvent(known).event?.id == known.eventID)
        let missing = await store.lookUpEvent(unknown)
        #expect(missing.event == nil && missing.fallbackNote == RelayEventLookup.notPaired.fallbackNote)
    }

    @Test func readsTheRelayPushPayload() throws {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "严重：账户风控", "body": "11-09 23:00 悉尼 / 20:00 北京\n量化账户触发保护检查"],
                    "sound": "default", "thread-id": "portsight", "interruption-level": "time-sensitive"],
            "event_id": "forward_lockbox_audit@2026-11-09T12:00Z",
        ]
        let ref = try #require(PushEventRef(userInfo: userInfo))
        #expect(ref.eventID == "forward_lockbox_audit@2026-11-09T12:00Z")
        #expect(ref.title == "严重：账户风控")
        #expect(ref.body.hasSuffix("量化账户触发保护检查"))
        #expect(PushEventRef.kind(of: ref.eventID!) == "forward_lockbox_audit")
        #expect(PushEventRef.kind(of: "no_time") == "no_time")
        // A string alert still works; a notification that is not ours does not.
        #expect(PushEventRef(userInfo: ["aps": ["alert": "正文"]])?.body == "正文")
        #expect(PushEventRef(userInfo: ["other": 1]) == nil)
    }

    @Test func eventsDecodeTheirDetailToleratingOddTypes() throws {
        let json = #"""
        {"events": [
          {"id": "disk_full@2026-11-09T01:00Z", "title": "照片盘未挂载", "severity": "warning", "category": "ops",
           "source": "host-status", "at": "2026-11-09T01:00:00Z", "detail": {"volume": "/Volumes/照片", "free_gb": 12.5, "mounted": false}},
          {"id": "disk_full@2026-11-08T01:00Z", "detail": {}},
          {"id": "odd@2026-11-08T02:00Z", "detail": "not an object", "severity": 3}
        ]}
        """#
        let page = try JSONDecoder().decode(HostAlertPage.self, from: Data(json.utf8))
        #expect(page.events.count == 3)
        let first = page.events[0]
        #expect(first.kind == "disk_full")
        #expect(first.detailFacts.map(\.label) == ["free_gb", "mounted", "volume"])
        #expect(first.detailFacts.map(\.value) == ["12.5", "否", "/Volumes/照片"])
        #expect(page.events[1].detailFacts.isEmpty)
        #expect(page.events[2].detail == nil && page.events[2].severity == nil)
        // Round-trips for the on-disk cache.
        let again = try JSONDecoder().decode(HostEvent.self, from: JSONEncoder().encode(first))
        #expect(again == first)
    }

    /// 429 waits Retry-After (at least 30 s), 403 waits out the 10-minute lockout, nothing else waits.
    @Test func serverBackoff() {
        #expect(RelayAPI.backoff(status: 429, retryAfter: nil) == 30)
        #expect(RelayAPI.backoff(status: 429, retryAfter: "5") == 30)
        #expect(RelayAPI.backoff(status: 429, retryAfter: " 90 ") == 90)
        #expect(RelayAPI.backoff(status: 429, retryAfter: "Wed, 21 Oct 2026 07:28:00 GMT") == 30)
        #expect(RelayAPI.backoff(status: 403, retryAfter: nil) == 600)
        #expect(RelayAPI.backoff(status: 401, retryAfter: nil) == nil)
        #expect(RelayAPI.backoff(status: 200, retryAfter: "60") == nil)
        #expect(RelayFailure(ServerError.rateLimited) == .rateLimited)
        #expect(RelayFailure(ServerError.http(403)) == .locked)
        #expect(RelayFailure(ServerError.unauthorized) == .unauthorized)
        #expect(RelayFailure(ServerError.http(502)) == .server(502))
        #expect(RelayFailure(URLError(.timedOut)) == .network)
        #expect(!RelayFailure.network.message.contains("Tailscale"))
    }

    /// Network failure → 连不上服务器（检查手机网络）; reachable but stale → 服务器在线，但…超过 15 分钟没更新.
    @Test func connectionBanners() {
        let now = Date()
        let stale = ServerFreshness.evaluate(asOf: ISO8601DateFormatter().string(from: now.addingTimeInterval(-40 * 60)),
                                             now: now, staleAfterMinutes: 15)
        let fresh = ServerFreshness(state: .fresh)
        func banner(_ failure: RelayFailure?, _ freshness: ServerFreshness, reached: Bool = true) -> RelayConnectionBanner? {
            RelayConnectionBanner.make(failure: failure, networkHint: "手机网络", savedAt: now, hasData: true,
                                       freshness: freshness, staleAfterMinutes: 15, blockedUntil: nil, reachedServer: reached)
        }
        #expect(banner(nil, fresh) == nil)
        #expect(banner(.network, fresh)?.title == "连不上服务器（检查手机网络）")
        // Offline wins over an old heartbeat: the server's state is unknown.
        #expect(banner(.network, stale)?.kind == .offline)
        #expect(banner(nil, stale)?.title == "服务器在线，但 Mac mini 的状态超过 15 分钟没更新")
        #expect(banner(nil, stale, reached: false)?.title == "Mac mini 的状态超过 15 分钟没更新")
        #expect(banner(.rateLimited, fresh)?.kind == .rateLimited)
        #expect(banner(.server(500), fresh)?.title == "服务器出错（500）")
        #expect(banner(.unauthorized, fresh) == nil)
    }

    /// The offline cache round-trips host, synced alerts (newest 500), good feed answers and the read time; failed
    /// feed states are not kept; deleting removes it.
    @Test func relayCacheRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("server_cache.json")
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = try JSONDecoder().decode(HostStatus.self, from: Data(ServerSample.json.utf8))
        let event = try #require(host.alerts_recent?.first)
        let events = Array(repeating: event, count: 600)
        let at = Date(timeIntervalSince1970: 1_794_000_000)
        let cache = RelayCache(base: "https://relay.example.ts.net", host: host, events: events,
                               feeds: [.status: .received(asOf: "2026-11-11T08:00:00Z"), .advice: .failed("连不上"),
                                       .account: .noData],
                               fetchedAt: at)
        #expect(cache.events.count == 500)
        cache.save(to: url)
        let back = try #require(RelayCache.load(from: url))
        #expect(back == cache)
        #expect(back.host == host && back.fetchedAt == at)
        #expect(back.feedStates == [.status: .received(asOf: "2026-11-11T08:00:00Z"), .account: .noData])
        RelayCache.delete(at: url)
        #expect(RelayCache.load(from: url) == nil)
    }
}
