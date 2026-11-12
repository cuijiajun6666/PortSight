import Foundation
import Testing
@testable import PortSightKit

// MARK: - Fixtures (shapes from the Immich v3.3.6 OpenAPI spec)

private let bucketsJSON = Data("""
[{"timeBucket": "2026-09-01", "count": 2}, {"timeBucket": "2026-10-01", "count": 4}, {"timeBucket": "2026-11-01", "count": 0}]
""".utf8)

/// Columnar time bucket, newest first like the server's default order, with the undocumented `status` key.
private let octoberJSON = Data("""
{"duration": [15832, null, null, null],
 "id": ["3f9d2b7a-1c4e-4a8b-9e6f-0d2c5b8a7e13", "b71e4c09-5a3d-4f2e-8c61-9d0a7e3b5f24",
        "e2a95d3c-8f17-4b40-b6d9-7c3e0a1f4b58", "a6c3f0e8-2d51-4b7a-9f04-6e8b1d3c5a72"],
 "visibility": ["timeline", "timeline", "timeline", "timeline"],
 "isFavorite": [false, true, false, false],
 "isImage": [false, true, true, true],
 "isTrashed": [false, false, false, false],
 "livePhotoVideoId": [null, "c4e18f52-7b0d-4a96-a3e5-1f8c2d6b9a07", null, null],
 "fileCreatedAt": ["2026-10-28T10:42:10.517", "2026-10-19T00:15:03.842", "2026-10-11T14:30:00", "2026-10-03T16:35:11.06"],
 "localOffsetHours": [8, 9, -7, 5.5],
 "createdAt": ["2026-10-28T11:02:47.193214", "2026-10-19T03:20:11.208", "2026-10-12T02:14:55.73", "2026-10-03T16:35:40.481"],
 "ownerId": ["8a2f6c1e-4b7d-4e93-9c0a-5d1e7f3b2a64", "8a2f6c1e-4b7d-4e93-9c0a-5d1e7f3b2a64",
             "8a2f6c1e-4b7d-4e93-9c0a-5d1e7f3b2a64", "8a2f6c1e-4b7d-4e93-9c0a-5d1e7f3b2a64"],
 "projectionType": [null, null, null, null],
 "ratio": [0.563, 0.75, 1.5, 0],
 "status": ["active", "active", "active", "active"],
 "thumbhash": ["3jgORAhnCIhniHl3eHh3gIcIdw==", null, null, null],
 "city": ["Shanghai", "Tokyo", "", null],
 "country": ["China", "Japan", null, null]}
""".utf8)

private let septemberJSON = Data("""
{"duration": [null, null], "id": ["11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222"],
 "isImage": [true, true], "ratio": [1.333, 0.75],
 "fileCreatedAt": ["2026-09-01T02:00:00", "2026-09-20T08:00:00.5"], "localOffsetHours": [8, 8],
 "livePhotoVideoId": [null, null], "visibility": ["timeline", "timeline"], "isFavorite": [false, false],
 "isTrashed": [false, false], "createdAt": ["2026-09-01T02:00:00", "2026-09-20T08:00:00"],
 "ownerId": ["8a2f6c1e-4b7d-4e93-9c0a-5d1e7f3b2a64", "8a2f6c1e-4b7d-4e93-9c0a-5d1e7f3b2a64"],
 "projectionType": [null, null], "thumbhash": [null, null]}
""".utf8)

private let driveJSON = """
{"client_id": "abc.apps.googleusercontent.com", "client_secret": "s", "refresh_token": "1//r",
 "folders": {"妈妈": "folderMom"}
"""

private func config(_ host: String = "photos.example.org") -> ImmichConfig {
    ImmichConfig(url: URL(string: "https://\(host)")!, apiKey: "read-only-key-123")
}

// MARK: - Configuration

@Suite struct ImmichConfigTests {
    @Test func readsTheImmichPartOfTheDriveConfig() throws {
        let parsed = try DriveConfig.parse(driveJSON + #", "immich": {"url": " https://photos.example.org/ ", "api_key": " k1 "}}"#)
        #expect(parsed.immich == ImmichConfig(url: URL(string: "https://photos.example.org")!, apiKey: "k1"))
        // Without it (or null) the configuration is the plain Drive one.
        #expect(try DriveConfig.parse(driveJSON + "}").immich == nil)
        #expect(try DriveConfig.parse(driveJSON + #", "immich": null}"#).immich == nil)
    }

    @Test func refusesAnythingButAnHTTPSBaseAddressAndAKey() {
        let bad: [(String, String)] = [
            (#"{"url": "http://photos.example.org", "api_key": "k"}"#, "url 只能是 https:// 开头的地址"),
            (#"{"url": "https://photos.example.org/api", "api_key": "k"}"#, "url 只写到域名，不要加 /api"),
            (#"{"url": "https://photos.example.org?x=1", "api_key": "k"}"#, "url 只能是 https:// 开头的地址"),
            (#"{"url": "https://photos.example.org", "api_key": ""}"#, "缺少 api_key"),
            (#"{"url": "https://photos.example.org", "api_key": "a b"}"#, "api_key 里不能有空格"),
            (#"{"api_key": "k"}"#, "缺少 url"),
            (#""https://photos.example.org""#, "应该是一个对象"),
        ]
        for (immich, detail) in bad {
            #expect(throws: DriveConfigError.invalidImmich(detail)) {
                try DriveConfig.parse(driveJSON + #", "immich": "# + immich + "}")
            }
        }
    }

    /// The key must survive the keychain round trip (canonical JSON) and never show in descriptions.
    @Test func keepsTheKeyThroughSavingButNeverPrintsIt() throws {
        let parsed = try DriveConfig.parse(driveJSON + #", "immich": {"url": "https://photos.example.org:8443", "api_key": "secret-key"}}"#)
        let again = try DriveConfig.parse(try #require(parsed.canonicalJSON))
        #expect(again == parsed)
        #expect(again.immich?.url.absoluteString == "https://photos.example.org:8443")
        for text in ["\(parsed)", String(reflecting: parsed), "\(parsed.immich!)", String(reflecting: parsed.immich!)] {
            #expect(!text.contains("secret-key"))
        }
    }
}

// MARK: - Requests and responses

@Suite struct ImmichAPITests {
    @Test func requestsCarryTheKeyOnlyInTheHeader() throws {
        let c = config()
        let buckets = ImmichAPI.bucketsRequest(c)
        #expect(buckets.url?.absoluteString == "https://photos.example.org/api/timeline/buckets?visibility=timeline&order=asc")
        let bucket = ImmichAPI.bucketRequest(c, timeBucket: "2026-10-01")
        #expect(bucket.url?.absoluteString
                == "https://photos.example.org/api/timeline/bucket?timeBucket=2026-10-01T00:00:00.000Z&visibility=timeline&order=asc")
        let image = ImmichAPI.imageRequest(c, assetID: "3f9d2b7a-1c4e-4a8b-9e6f-0d2c5b8a7e13", size: .preview)
        #expect(image.url?.absoluteString
                == "https://photos.example.org/api/assets/3f9d2b7a-1c4e-4a8b-9e6f-0d2c5b8a7e13/thumbnail?size=preview")
        #expect(image.cachePolicy == .returnCacheDataElseLoad)
        let video = try #require(ImmichAPI.playbackURL(c, assetID: "3f9d2b7a-1c4e-4a8b-9e6f-0d2c5b8a7e13"))
        #expect(video.absoluteString == "https://photos.example.org/api/assets/3f9d2b7a-1c4e-4a8b-9e6f-0d2c5b8a7e13/video/playback")
        for request in [buckets, bucket, image] {
            #expect(request.value(forHTTPHeaderField: "x-api-key") == "read-only-key-123")
            #expect(request.url?.absoluteString.contains("read-only-key") == false)
            #expect(request.httpMethod == "GET")
        }
        #expect(ImmichAPI.headers(c) == ["x-api-key": "read-only-key-123"])
    }

    @Test func keepsAPathPrefixAndCannotBeSteeredByAnID() {
        let c = ImmichConfig(url: URL(string: "https://example.org/immich")!, apiKey: "k")
        #expect(ImmichAPI.bucketsRequest(c).url?.path == "/immich/api/timeline/buckets")
        let request = ImmichAPI.imageRequest(c, assetID: "../../users/me?x=1", size: .thumbnail)
        #expect(request.url?.path == "/immich/api/assets/ee1/thumbnail")
    }

    @Test func readsTheMonthsAndSkipsEmptyOnes() throws {
        let buckets = try ImmichAPI.parseBuckets(status: 200, body: bucketsJSON)
        #expect(buckets.map(\.timeBucket) == ["2026-09-01", "2026-10-01"])
        #expect(buckets.map(\.count) == [2, 4])
        #expect(buckets[1].year == 2026 && buckets[1].month == 10)
    }

    @Test func readsAColumnarMonth() throws {
        let assets = try ImmichAPI.parseBucket(status: 200, body: octoberJSON)
        #expect(assets.count == 4)
        let video = assets[0]
        #expect(!video.isImage && video.durationMs == 15832 && video.city == "Shanghai")
        #expect(video.ratio == 0.563 && video.localOffsetHours == 8)
        #expect(assets[1].livePhotoVideoID == "c4e18f52-7b0d-4a96-a3e5-1f8c2d6b9a07")
        #expect(assets[2].city == nil)                     // empty string
        #expect(assets[3].ratio == 1)                      // not processed yet
        #expect(assets[3].localOffsetHours == 5.5)
        #expect(assets[0].takenAtUTC == ImmichAPI.date("2026-10-28T10:42:10.517Z"))
    }

    @Test func mapsErrorsToWhatTheFamilyCanDo() {
        #expect(throws: ImmichError.unauthorized) { try ImmichAPI.parseBuckets(status: 401, body: Data()) }
        #expect(throws: ImmichError.forbidden) { try ImmichAPI.parseBucket(status: 403, body: Data()) }
        #expect(throws: ImmichError.http(500)) { try ImmichAPI.parseBuckets(status: 500, body: Data()) }
        #expect(throws: ImmichError.badResponse) { try ImmichAPI.parseBuckets(status: 200, body: Data("<html>".utf8)) }
        // Arrays of different lengths are not a month.
        let broken = Data(#"{"id": ["a"], "isImage": [], "ratio": [1], "fileCreatedAt": ["2026-10-01T00:00:00"], "localOffsetHours": [0], "duration": [null], "livePhotoVideoId": [null]}"#.utf8)
        #expect(throws: ImmichError.badResponse) { try ImmichAPI.parseBucket(status: 200, body: broken) }
    }

    @Test func readsEveryImmichDateFormat() throws {
        let base = try #require(ImmichAPI.date("2026-10-19T00:15:03Z"))
        #expect(ImmichAPI.date("2026-10-19T00:15:03") == base)
        #expect(ImmichAPI.date("2026-10-19T00:15:03.842Z")?.timeIntervalSince(base) ?? 0 > 0.8419)
        #expect(ImmichAPI.date("2026-10-19T00:15:03.842+00:00") == ImmichAPI.date("2026-10-19T00:15:03.842Z"))
        #expect(ImmichAPI.date("2026-10-19T08:15:03+08:00") == base)
        #expect(ImmichAPI.date("2026-10-18T21:15:03-0300") == base)
        #expect(ImmichAPI.date("2026-10-19T00:15:03.193214")?.timeIntervalSince(base) ?? 0 > 0.193)
        for bad in ["", "2026-10-19", "2026-10-19T00:15", "2026-10-19T00:15:03X", "abcd-10-19T00:15:03"] {
            #expect(ImmichAPI.date(bad) == nil)
        }
    }

    /// A photo keeps its real moment and where it was taken: shown in that offset, 01:30 UTC taken in Hangzhou
    /// reads 9:30 on Oct 11 whatever the phone's own time zone is (and after the phone changes zone).
    @Test func showsThePhotographersClockTime() throws {
        let asset = try #require(ImmichAPI.parseBucket(status: 200, body: octoberJSON).first)
        let photo = FamilyLibrary.photo(asset)
        #expect(photo.date == asset.takenAtUTC)
        let utc = try #require(ImmichAPI.date("2026-10-11T01:30:00"))
        let remote = FamilyRemoteAsset(ratio: 1, durationMs: nil, livePhotoVideoID: nil, city: nil, localOffsetHours: 8)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = remote.timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: utc)
        #expect(parts == DateComponents(year: 2026, month: 10, day: 11, hour: 9, minute: 30))
        #expect(FamilyRemoteAsset(ratio: 1, durationMs: nil, livePhotoVideoID: nil, city: nil, localOffsetHours: 5.5)
                    .timeZone.secondsFromGMT() == 19_800)
        #expect(FamilyRemoteAsset(ratio: 1, durationMs: nil, livePhotoVideoID: nil, city: nil, localOffsetHours: -9.75)
                    .timeZone.secondsFromGMT() == -35_100)
    }
}

// MARK: - Library

/// Answers https://<anything>.immich.test with canned responses per host and path.
final class MockImmich: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var routes: [String: (Int, Data)] = [:]
    nonisolated(unsafe) static var keys: [String] = []
    nonisolated static let lock = NSLock()

    nonisolated static func set(_ host: String, _ path: String, _ status: Int, _ body: Data) {
        lock.withLock { routes[host + path] = (status, body) }
    }

    nonisolated override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".immich.test") == true
    }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    nonisolated override func startLoading() {
        guard let url = request.url, let host = url.host else { return }
        let route = Self.lock.withLock { () -> (Int, Data)? in
            Self.keys.append(request.value(forHTTPHeaderField: "x-api-key") ?? "")
            return Self.routes[host + url.path]
        }
        guard let (status, body) = route else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    nonisolated override func stopLoading() {}
}

@Suite(.serialized) struct FamilyLibraryTests {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockImmich.self]
        return URLSession(configuration: configuration)
    }

    private func cacheFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("family-\(UUID().uuidString)/library.json")
    }

    private func until(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func demoLibraryFillsEverySlot() {
        let library = FamilyLibrary(session: session(), cacheFile: nil, loadConfig: { nil })
        library.start()
        #expect(library.status == .demo && !library.isRemote)
        #expect(library.slots.count == DemoFamilyData.photos.count)
        #expect(library.totalCount == DemoFamilyData.photos.count)
        let dates = library.slots.compactMap { library.photo(at: $0)?.date }
        #expect(dates.count == library.slots.count && dates == dates.sorted())
        #expect(library.months == library.months.sorted { ($0.year, $0.month) < ($1.year, $1.month) })
        let slot = library.slots[3]
        #expect(FamilyLibrarySlot(id: slot.id) == slot)
        #expect(library.photo(slotID: slot.id) == library.photo(at: slot))
        #expect(FamilyLibrarySlot(id: "2026-10") == nil && FamilyLibrarySlot(id: "2026-10#x") == nil)
    }

    @Test func immichMonthsComeFirstThenEachMonthOnDemand() async throws {
        let host = "a.immich.test"
        MockImmich.set(host, "/api/timeline/buckets", 200, bucketsJSON)
        MockImmich.set(host, "/api/timeline/bucket", 200, octoberJSON)   // the query picks the month; one is enough here
        let library = FamilyLibrary(session: session(), cacheFile: cacheFile(), loadConfig: { config(host) })
        library.start()
        #expect(library.status == .connecting && library.isRemote && library.host == host)
        await until { library.status == .ready && library.loaded["2026-10"] != nil }
        #expect(library.months.map(\.id) == ["2026-9", "2026-10"])
        #expect(library.slots.map(\.id) == ["2026-9#0", "2026-9#1", "2026-10#0", "2026-10#1", "2026-10#2", "2026-10#3"])
        // The newest month loads by itself, oldest first.
        let october = try #require(library.loaded["2026-10"])
        #expect(october.map(\.id).last == "3f9d2b7a-1c4e-4a8b-9e6f-0d2c5b8a7e13")
        #expect(october.last?.isVideo == true && october.last?.remote?.durationMs == 15832)
        #expect(october.allSatisfy { $0.remote != nil && $0.caption.isEmpty })
        #expect(library.loaded["2026-9"] == nil)
        // A month whose photos differ from its count gets exactly its photos' places.
        MockImmich.set(host, "/api/timeline/bucket", 200, octoberJSON)
        library.ensureLoaded("2026-9")
        await until { library.loaded["2026-9"] != nil }
        #expect(library.months.first?.count == 4)
        #expect(library.slots.count == 8)
        #expect(MockImmich.lock.withLock { MockImmich.keys.allSatisfy { $0 == "read-only-key-123" } })
    }

    @Test func aRefusedKeySaysSoAndTheLastLibraryStaysWhenOffline() async throws {
        let host = "b.immich.test"
        let file = cacheFile()
        MockImmich.set(host, "/api/timeline/buckets", 200, bucketsJSON)
        MockImmich.set(host, "/api/timeline/bucket", 200, septemberJSON)
        let first = FamilyLibrary(session: session(), cacheFile: file, loadConfig: { config(host) })
        first.start()
        await until { first.status == .ready && first.loaded["2026-10"] != nil }
        try? await Task.sleep(for: .seconds(2.5))                       // the cache is written a moment later
        #expect(FileManager.default.fileExists(atPath: file.path))
        let cached = try String(contentsOf: file, encoding: .utf8)
        #expect(!cached.contains("read-only-key"))

        // Offline: the last library shows (read off the main thread), with the reason.
        MockImmich.lock.withLock { MockImmich.routes[host + "/api/timeline/buckets"] = nil }
        let offline = FamilyLibrary(session: session(), cacheFile: file, loadConfig: { config(host) })
        offline.start()
        await until { offline.status != .connecting && !offline.slots.isEmpty }
        #expect(offline.slots.count == first.slots.count && offline.loaded["2026-10"] != nil)
        #expect(offline.status == .failed(.unreachable))

        // A different server or key: the last library is dropped, not shown.
        let fresh = FamilyLibrary(session: session(), cacheFile: file, loadConfig: { config(host) })
        fresh.reload(discardingCache: true)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(fresh.slots.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        try (try #require(cached.data(using: .utf8))).write(to: file)  // put it back for the clearing check below

        // A deleted key.
        MockImmich.set(host, "/api/timeline/buckets", 401, Data())
        let refused = FamilyLibrary(session: session(), cacheFile: nil, loadConfig: { config(host) })
        refused.start()
        await until { refused.status != .connecting }
        #expect(refused.status == .failed(.unauthorized))

        // Cleared configuration: back to the demo, and the cached library is gone.
        let cleared = FamilyLibrary(session: session(), cacheFile: file, loadConfig: { nil })
        cleared.start()
        #expect(cleared.status == .demo)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
