import Foundation
import Testing
@testable import PortSightKit

@Suite struct DriveUploadTests {
    private let goodJSON = """
    {"client_id": "abc.apps.googleusercontent.com",
     "client_secret": "sec+ret/with=&chars",
     "refresh_token": "1//refresh",
     "folders": {"妈妈": "folderMom", "爸爸": "folderDad"},
     "extra": 1}
    """

    private func config() throws -> DriveConfig { try DriveConfig.parse(goodJSON) }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int, tz: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: tz)!
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi, second: s))!
    }

    // MARK: config

    @Test func parsesGoodJSON() throws {
        let c = try config()
        #expect(c.clientID == "abc.apps.googleusercontent.com")
        #expect(c.clientSecret == "sec+ret/with=&chars")
        #expect(c.refreshToken == "1//refresh")
        #expect(c.folders == ["妈妈": "folderMom", "爸爸": "folderDad"])
    }

    @Test func parsesSmartQuotesAndWhitespace() throws {
        let text = "  \n{“client_id”: “ id ”, “client_secret”: “s”, “refresh_token”: “r”, “folders”: {“ 妈妈 ”: “ f1 ”}}\n "
        let c = try DriveConfig.parse(text)
        #expect(c.clientID == "id")
        #expect(c.folders == ["妈妈": "f1"])
    }

    @Test func rejectsMissingFields() {
        #expect(throws: DriveConfigError.missingField("client_id")) {
            try DriveConfig.parse(#"{"client_secret":"s","refresh_token":"r","folders":{"a":"b"}}"#)
        }
        #expect(throws: DriveConfigError.missingField("client_secret")) {
            try DriveConfig.parse(#"{"client_id":"i","client_secret":"  ","refresh_token":"r","folders":{"a":"b"}}"#)
        }
        #expect(throws: DriveConfigError.missingField("refresh_token")) {
            try DriveConfig.parse(#"{"client_id":"i","client_secret":"s","folders":{"a":"b"}}"#)
        }
        #expect(throws: DriveConfigError.missingField("folders")) {
            try DriveConfig.parse(#"{"client_id":"i","client_secret":"s","refresh_token":"r"}"#)
        }
        #expect(throws: DriveConfigError.self) {
            try DriveConfig.parse(#"{"client_id":"i","client_secret":"s","refresh_token":"r","folders":{"a":""}}"#)
        }
        #expect(DriveConfigError.missingField("client_id").message == "缺少 client_id")
    }

    @Test func rejectsEmptyFoldersAndNonJSON() {
        #expect(throws: DriveConfigError.noFolders) {
            try DriveConfig.parse(#"{"client_id":"i","client_secret":"s","refresh_token":"r","folders":{}}"#)
        }
        #expect(throws: DriveConfigError.notJSON) { try DriveConfig.parse("client_id: abc") }
        #expect(throws: DriveConfigError.notJSON) { try DriveConfig.parse("[1, 2]") }
        #expect(DriveConfigError.notJSON.message == "不是有效的 JSON，请整段复制粘贴")
        #expect(DriveConfigError.noFolders.message == "folders 里没有家人")
    }

    @Test func membersAreSortedAndDescriptionHidesSecrets() throws {
        let c = DriveConfig(clientID: "i", clientSecret: "TOPSECRET", refreshToken: "REFRESH",
                            folders: ["家人10": "a", "家人2": "b", "Bob": "c", "alice": "d", "file10": "e", "file9": "f"])
        #expect(c.members.filter { $0.hasPrefix("家人") } == ["家人2", "家人10"])
        #expect(c.members.filter { $0.first?.isASCII == true } == ["alice", "Bob", "file9", "file10"])
        let text = "\(c) \(String(reflecting: c))"
        #expect(!text.contains("TOPSECRET"))
        #expect(!text.contains("REFRESH"))
    }

    @Test func canonicalJSONRoundTrips() throws {
        let c = try config()
        let json = try #require(c.canonicalJSON)
        #expect(try DriveConfig.parse(json) == c)
    }

    @Test func memberFolderLookup() throws {
        let c = try config()
        let saved = DriveMember.current
        defer { DriveMember.current = saved }
        DriveMember.current = "妈妈"
        #expect(DriveMember.folderID(in: c) == "folderMom")
        #expect(DriveMember.folderID(in: nil) == nil)
        DriveMember.current = "外婆"
        #expect(DriveMember.folderID(in: c) == nil)
        DriveMember.current = nil
        #expect(DriveMember.folderID(in: c) == nil)
    }

    // MARK: token

    @Test func tokenRequestIsFormEncoded() throws {
        let request = DriveAPI.tokenRequest(try config())
        #expect(request.url == DriveAPI.tokenURL)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body == "grant_type=refresh_token&client_id=abc.apps.googleusercontent.com"
                + "&client_secret=sec%2Bret%2Fwith%3D%26chars&refresh_token=1%2F%2Frefresh")
    }

    @Test func parseTokenCases() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let ok = try DriveAPI.parseToken(status: 200, body: Data(#"{"access_token":"ya29.x","expires_in":3599,"token_type":"Bearer"}"#.utf8), now: now)
        #expect(ok.value == "ya29.x")
        #expect(ok.expiresAt == now.addingTimeInterval(3599))
        #expect(ok.isValid(at: now))
        #expect(!ok.isValid(at: now.addingTimeInterval(3599 - 30)))
        #expect(throws: DriveError.invalidGrant) {
            try DriveAPI.parseToken(status: 400, body: Data(#"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#.utf8))
        }
        #expect(throws: DriveError.http(401)) {
            try DriveAPI.parseToken(status: 401, body: Data(#"{"error":"invalid_client"}"#.utf8))
        }
        #expect(throws: DriveError.http(500)) { try DriveAPI.parseToken(status: 500, body: Data()) }
        #expect(throws: DriveError.http(200)) { try DriveAPI.parseToken(status: 200, body: Data("{}".utf8)) }
    }

    // MARK: upload requests

    @Test func initiateRequestHeadersAndBody() throws {
        let takenAt = date(2026, 11, 9, 11, 30, 5, tz: "Asia/Shanghai")
        let request = DriveAPI.initiateRequest(fileName: "20261109_113005_1a2b3c4d_IMG_0001.HEIC", mimeType: "image/heic",
                                               size: 1_234_567, folderID: "folderMom", takenAt: takenAt, accessToken: "ya29.x")
        #expect(request.url == DriveAPI.initiateURL)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ya29.x")
        #expect(request.value(forHTTPHeaderField: "X-Upload-Content-Type") == "image/heic")
        #expect(request.value(forHTTPHeaderField: "X-Upload-Content-Length") == "1234567")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/json") == true)
        let httpBody = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: httpBody) as? [String: Any])
        #expect(json["name"] as? String == "20261109_113005_1a2b3c4d_IMG_0001.HEIC")
        #expect(json["parents"] as? [String] == ["folderMom"])
        #expect((json["appProperties"] as? [String: String])?["taken_at"] == "2026-11-09T03:30:05Z")
        #expect(DriveAPI.chunkSize % (256 * 1024) == 0)
    }

    @Test func sessionURLFromLocation() throws {
        let response = try #require(HTTPURLResponse(url: DriveAPI.initiateURL, statusCode: 200, httpVersion: nil,
                                                    headerFields: ["Location": "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=XYZ"]))
        #expect(DriveAPI.sessionURL(from: response)?.query?.contains("upload_id=XYZ") == true)
        let none = try #require(HTTPURLResponse(url: DriveAPI.initiateURL, statusCode: 200, httpVersion: nil, headerFields: [:]))
        #expect(DriveAPI.sessionURL(from: none) == nil)
    }

    @Test func chunkAndStatusContentRange() {
        let session = URL(string: "https://www.googleapis.com/upload/drive/v3/files?upload_id=1")!
        let chunk = DriveAPI.chunkRequest(sessionURL: session, offset: 8_388_608, length: 1000, total: 8_389_608)
        #expect(chunk.httpMethod == "PUT")
        #expect(chunk.value(forHTTPHeaderField: "Content-Range") == "bytes 8388608-8389607/8389608")
        #expect(chunk.value(forHTTPHeaderField: "Content-Length") == "1000")
        let status = DriveAPI.statusRequest(sessionURL: session, total: 8_389_608)
        #expect(status.httpMethod == "PUT")
        #expect(status.value(forHTTPHeaderField: "Content-Range") == "bytes */8389608")
        #expect(status.value(forHTTPHeaderField: "Content-Length") == "0")
        #expect(status.httpBody == nil)
    }

    @Test func outcomeMapping() {
        func body(_ s: String) -> Data { Data(s.utf8) }
        #expect(DriveAPI.outcome(status: 200, headers: [:], body: nil) == .completed)
        #expect(DriveAPI.outcome(status: 201, headers: [:], body: nil) == .completed)
        #expect(DriveAPI.outcome(status: 308, headers: ["Range": "bytes=0-8388607"], body: nil) == .resumeAt(8_388_608))
        #expect(DriveAPI.outcome(status: 308, headers: ["range": "bytes=0-0"], body: nil) == .resumeAt(1))
        #expect(DriveAPI.outcome(status: 308, headers: [:], body: nil) == .resumeAt(0))
        #expect(DriveAPI.outcome(status: 404, headers: [:], body: nil) == .sessionExpired)
        #expect(DriveAPI.outcome(status: 410, headers: [:], body: nil) == .sessionExpired)
        #expect(DriveAPI.outcome(status: 401, headers: [:], body: nil) == .unauthorized)
        let quota = #"{"error":{"code":403,"message":"The user's Drive storage quota has been exceeded.","errors":[{"domain":"usageLimits","reason":"storageQuotaExceeded"}]}}"#
        #expect(DriveAPI.outcome(status: 403, headers: [:], body: body(quota)) == .quotaExceeded)
        let rate = #"{"error":{"code":403,"errors":[{"domain":"usageLimits","reason":"userRateLimitExceeded"}]}}"#
        #expect(DriveAPI.outcome(status: 403, headers: [:], body: body(rate)) == .retryLater)
        let rate2 = #"{"error":{"code":403,"errors":[{"reason":"rateLimitExceeded"}]}}"#
        #expect(DriveAPI.outcome(status: 403, headers: [:], body: body(rate2)) == .retryLater)
        let other = #"{"error":{"code":403,"errors":[{"reason":"insufficientFilePermissions"}]}}"#
        #expect(DriveAPI.outcome(status: 403, headers: [:], body: body(other)) == .failed("上传失败（HTTP 403）"))
        #expect(DriveAPI.outcome(status: 403, headers: [:], body: nil) == .failed("上传失败（HTTP 403）"))
        #expect(DriveAPI.outcome(status: 408, headers: [:], body: nil) == .retryLater)
        #expect(DriveAPI.outcome(status: 429, headers: [:], body: nil) == .retryLater)
        #expect(DriveAPI.outcome(status: 500, headers: [:], body: nil) == .retryLater)
        #expect(DriveAPI.outcome(status: 503, headers: [:], body: nil) == .retryLater)
        #expect(DriveAPI.outcome(status: 400, headers: [:], body: nil) == .failed("上传失败（HTTP 400）"))
    }

    @Test func classifyTransportErrors() {
        for code: URLError.Code in [.timedOut, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
                                    .networkConnectionLost, .dnsLookupFailed, .secureConnectionFailed] {
            #expect(DriveAPI.classify(URLError(code)) == .unreachable)
        }
        #expect(DriveAPI.classify(DriveError.invalidGrant) == .invalidGrant)
        #expect(DriveAPI.classify(URLError(.cancelled)) != .unreachable)
        #expect(DriveError.unreachable.message == "请打开翻墙后重试")
        #expect(DriveError.quotaExceeded.message == "云盘暂时满了，稍后自动重试")
        #expect(DriveError.invalidGrant.message == "请让管理员重新配置")
        #expect(DriveError.http(500).message == "上传失败（HTTP 500）")
    }

    // MARK: backoff, names, store

    @Test func backoffDoublesAndCapsAtTenMinutes() {
        var backoff = DriveBackoff()
        var delays: [TimeInterval] = []
        for _ in 0..<10 { delays.append(backoff.delay); backoff.fail() }
        #expect(delays == [5, 10, 20, 40, 80, 160, 320, 600, 600, 600])
        #expect(DriveBackoff(attempt: Int.max).delay == 600)
        var saturated = DriveBackoff(attempt: Int.max)
        saturated.fail()
        #expect(saturated.attempt == Int.max)
        backoff.reset()
        #expect(backoff.delay == 5)
    }

    @Test func fileNameMatchesContractExample() {
        let takenAt = date(2026, 11, 9, 11, 30, 5, tz: "Asia/Shanghai")
        let name = DriveFileName.make(takenAt: takenAt, assetID: "1A2B3C4D-5E6F-7081-92A3-B4C5D6E7F809/L0/001",
                                      originalName: "IMG_0001.HEIC", timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        #expect(name == "20261109_113005_1a2b3c4d_IMG_0001.HEIC")
        let video = DriveFileName.make(takenAt: takenAt, assetID: "1A2B3C4D-5E6F-7081-92A3-B4C5D6E7F809/L0/001",
                                       originalName: "IMG_0001.MOV", timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        #expect(video.hasPrefix("20261109_113005_1a2b3c4d_"))
        #expect(DriveFileName.make(takenAt: takenAt, assetID: "AB-CD", originalName: "a/b:c",
                                   timeZone: TimeZone(identifier: "UTC")!) == "20261109_033005_abcd_a_b_c")
        #expect(DriveFileName.make(takenAt: takenAt, assetID: "12345678", originalName: "",
                                   timeZone: TimeZone(identifier: "UTC")!).hasSuffix("_12345678_file"))
    }

    @Test func storeRoundTripsInTempDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DriveUploadTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DriveUploadStore(url: dir.appendingPathComponent("nested/queue.json"))
        #expect(store.load().isEmpty)

        var job = DriveUploadJob(assetID: "A/L0/001", fileName: "x.HEIC", mimeType: "image/heic", folderID: "f",
                                 member: "妈妈", takenAt: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(job.state == .preparing)
        #expect(job.progress == 0)
        job.totalBytes = 200
        job.sentBytes = 50
        job.sessionURL = URL(string: "https://www.googleapis.com/upload/drive/v3/files?upload_id=1")
        job.state = .uploading
        job.backoff.fail()
        #expect(job.progress == 0.25)
        let sent = DriveUploadJob(assetID: "B", fileName: "y.MOV", mimeType: "video/quicktime", folderID: "f",
                                  member: "爸爸", takenAt: .now)
        try store.save([job, sent])
        #expect(store.load() == [job, sent])

        try Data("garbage".utf8).write(to: store.url)
        #expect(store.load().isEmpty)
        #expect(DriveUploadStore.defaultURL.path.hasSuffix("DriveUploads/queue.json"))
    }
}
