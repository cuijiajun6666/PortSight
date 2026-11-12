import Foundation
import Testing
@testable import PortSight
import PortSightKit

@MainActor
struct ServerTests {
    private func sample() throws -> HostStatus {
        try JSONDecoder().decode(HostStatus.self, from: Data(ServerSample.json.utf8))
    }

    @Test func decodesTheHostStatusSample() throws {
        let h = try sample()
        #expect(h.host?.hostname == "mac-mini")
        #expect(h.summary?.state == "warning")
        #expect(h.disks?["main"]??.mounted == true && h.disks?["backup"]??.mounted == false)
        #expect(h.disks?["local_fallback"]??.files == 0)
        #expect(h.heartbeats?.contains { $0.name == "forward15m" && $0.state == "stale" } == true)
        #expect((h.history?.count ?? 0) >= 2 && h.history?.last?.load5 != nil)
        #expect(h.launchd?.jobs?["com.personalquant.relay"]?.state == "running")
    }

    @Test func toleratesUnknownAndMissingFields() throws {
        let h = try JSONDecoder().decode(HostStatus.self, from: Data(#"{"available": false, "message": "主机状态尚未接入", "new_field": [1, 2]}"#.utf8))
        #expect(h.available == false && h.heartbeats == nil)
        let p = try JSONDecoder().decode([HostHistoryPoint].self, from: Data(#"[["2026-11-03T02:00:00Z", null, 55]]"#.utf8))
        #expect(p[0].load5 == nil && p[0].memFreePct == 55)
    }

    @Test func freshnessUsesThePhoneClock() {
        let beat = "2026-11-03T02:00:00Z"
        let base = ServerDates.parse(beat)!
        #expect(ServerFreshness.evaluate(asOf: beat, now: base.addingTimeInterval(14 * 60), staleAfterMinutes: 15).state == .fresh)
        let late = ServerFreshness.evaluate(asOf: beat, now: base.addingTimeInterval(16 * 60), staleAfterMinutes: 15)
        #expect(late.state == .stale && abs((late.ageMinutes ?? 0) - 16) < 0.01)
        #expect(ServerFreshness.evaluate(asOf: nil, now: base, staleAfterMinutes: 15).state == .unknown)
        // Python isoformat with microseconds and an offset
        #expect(ServerDates.parse("2026-11-03T02:00:00.123456+00:00") == base)
    }

    @Test func pushTokenIsLowercaseHex() {
        #expect(ServerPush.hex(Data([0x00, 0xab, 0x10, 0xff])) == "00ab10ff")
    }

    @Test func backendNeedsAnHTTPSAddress() {
        let key = BackendConfig.storageKey
        let saved = UserDefaults.standard.string(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        UserDefaults.standard.removeObject(forKey: key)
        #expect(BackendConfig.defaultBaseURL.isEmpty && !BackendConfig.baseURLString.contains("45.63"))
        #expect(BackendConfig.normalize("mac-mini.tail1234.ts.net:8000") == "https://mac-mini.tail1234.ts.net:8000")
    }

    @Test func relayURLMustBePlainHTTPSOrigin() {
        #expect(ServerStore.normalizedURL("https://Mac-Mini.tail1234.ts.net/") == "https://mac-mini.tail1234.ts.net")
        #expect(ServerStore.normalizedURL("https://mac-mini.tail1234.ts.net:8443") == "https://mac-mini.tail1234.ts.net:8443")
        #expect(ServerStore.normalizedURL("http://mac-mini.tail1234.ts.net") == nil)
        #expect(ServerStore.normalizedURL("https://user:pw@mac-mini.ts.net") == nil)
        #expect(ServerStore.normalizedURL("https://mac-mini.ts.net/host?x=1") == nil)
    }
}
