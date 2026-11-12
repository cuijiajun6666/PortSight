import Foundation

/// An OAuth access token, kept in memory only (contract §3.1).
public nonisolated struct DriveAccessToken: Equatable, Sendable {
    public let value: String
    public let expiresAt: Date

    public init(value: String, expiresAt: Date) {
        self.value = value
        self.expiresAt = expiresAt
    }

    /// False within 60 s of expiry.
    public func isValid(at now: Date = .now) -> Bool {
        now.addingTimeInterval(60) < expiresAt
    }
}

/// Pure request builders and response interpreters for the Drive resumable upload (contract §3). No networking here.
public nonisolated enum DriveAPI {
    public static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    public static let initiateURL = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable")!
    /// 8 MiB, a multiple of 256 KiB.
    public static let chunkSize: Int64 = 8 * 1024 * 1024

    /// RFC 3986 unreserved characters; everything else (+ / = & …) is percent-encoded.
    private static let formAllowed: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return set
    }()

    static func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? ""
    }

    public static func tokenRequest(_ config: DriveConfig) -> URLRequest {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let fields = [("grant_type", "refresh_token"), ("client_id", config.clientID),
                      ("client_secret", config.clientSecret), ("refresh_token", config.refreshToken)]
        request.httpBody = Data(fields.map { "\($0.0)=\(formEncode($0.1))" }.joined(separator: "&").utf8)
        return request
    }

    public static func parseToken(status: Int, body: Data, now: Date = .now) throws -> DriveAccessToken {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        if status == 200, let value = json?["access_token"] as? String, !value.isEmpty {
            let seconds = (json?["expires_in"] as? NSNumber)?.doubleValue ?? 3600
            return DriveAccessToken(value: value, expiresAt: now.addingTimeInterval(seconds))
        }
        if (json?["error"] as? String) == "invalid_grant" { throw DriveError.invalidGrant }
        throw DriveError.http(status)
    }

    /// {"name":…, "parents":[folderID], "appProperties":{"taken_at": ISO-8601}}
    public static func initiateBody(fileName: String, folderID: String, takenAt: Date) -> Data {
        let object: [String: Any] = ["name": fileName, "parents": [folderID],
                                     "appProperties": ["taken_at": takenAt.formatted(.iso8601)]]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }

    public static func initiateRequest(fileName: String, mimeType: String, size: Int64, folderID: String,
                                       takenAt: Date, accessToken: String) -> URLRequest {
        var request = URLRequest(url: initiateURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue(String(size), forHTTPHeaderField: "X-Upload-Content-Length")
        request.httpBody = initiateBody(fileName: fileName, folderID: folderID, takenAt: takenAt)
        return request
    }

    /// The `Location` header of the initiate response is the upload session URL.
    public static func sessionURL(from response: HTTPURLResponse) -> URL? {
        guard let value = response.value(forHTTPHeaderField: "Location"), !value.isEmpty else { return nil }
        return URL(string: value)
    }

    /// PUT with Content-Range "bytes <offset>-<offset+length-1>/<total>"; Content-Length = length.
    public static func chunkRequest(sessionURL: URL, offset: Int64, length: Int64, total: Int64) -> URLRequest {
        var request = URLRequest(url: sessionURL)
        request.httpMethod = "PUT"
        request.setValue(String(length), forHTTPHeaderField: "Content-Length")
        request.setValue("bytes \(offset)-\(offset + length - 1)/\(total)", forHTTPHeaderField: "Content-Range")
        return request
    }

    /// PUT, empty body, Content-Range "bytes */<total>": asks how far the upload got.
    public static func statusRequest(sessionURL: URL, total: Int64) -> URLRequest {
        var request = URLRequest(url: sessionURL)
        request.httpMethod = "PUT"
        request.setValue("0", forHTTPHeaderField: "Content-Length")
        request.setValue("bytes */\(total)", forHTTPHeaderField: "Content-Range")
        return request
    }

    private static func header(_ name: String, in headers: [AnyHashable: Any]) -> String? {
        for (key, value) in headers {
            if let key = key as? String, key.caseInsensitiveCompare(name) == .orderedSame { return value as? String }
        }
        return nil
    }

    /// Error reasons / status strings in a Google JSON error body.
    private static func errorReasons(_ body: Data?) -> [String] {
        guard let body, let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return [] }
        var reasons: [String] = []
        if let error = json["error"] as? [String: Any] {
            if let errors = error["errors"] as? [[String: Any]] {
                reasons += errors.compactMap { $0["reason"] as? String }
            }
            if let status = error["status"] as? String { reasons.append(status) }
            if let message = error["message"] as? String { reasons.append(message) }
            if let details = error["details"] as? [[String: Any]] {
                reasons += details.compactMap { $0["reason"] as? String }
            }
        } else if let error = json["error"] as? String {
            reasons.append(error)
        }
        return reasons
    }

    /// Interprets any response to a chunk PUT, status PUT or the initiate POST.
    public static func outcome(status: Int, headers: [AnyHashable: Any], body: Data?) -> DriveUploadOutcome {
        switch status {
        case 200, 201:
            return .completed
        case 308:
            guard let range = header("Range", in: headers),
                  let last = range.split(separator: "-").last.flatMap({ Int64($0.trimmingCharacters(in: .whitespaces)) })
            else { return .resumeAt(0) }
            return .resumeAt(last + 1)
        case 401:
            return .unauthorized
        case 403:
            let reasons = errorReasons(body)
            if reasons.contains(where: { $0.localizedCaseInsensitiveContains("storageQuotaExceeded") }) { return .quotaExceeded }
            if reasons.contains(where: {
                $0.localizedCaseInsensitiveContains("rateLimitExceeded") || $0 == "RESOURCE_EXHAUSTED"
            }) { return .retryLater }
            return .failed("上传失败（HTTP 403）")
        case 404, 410:
            return .sessionExpired
        case 408, 429, 500...599:
            return .retryLater
        default:
            return .failed("上传失败（HTTP \(status)）")
        }
    }

    /// Maps a transport error to a DriveError; network-ish failures become `.unreachable` (翻墙 not on).
    public static func classify(_ error: Error) -> DriveError {
        if let error = error as? DriveError { return error }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: ns.code) {
            case .cancelled, .badURL, .unsupportedURL, .fileDoesNotExist, .noPermissionsToReadFile,
                 .dataLengthExceedsMaximum, .cannotDecodeRawData, .cannotDecodeContentData, .cannotParseResponse,
                 .userAuthenticationRequired, .userCancelledAuthentication:
                return .http(ns.code)
            default:
                // timedOut, notConnectedToInternet, cannotConnectToHost, cannotFindHost, networkConnectionLost,
                // dnsLookupFailed, secureConnectionFailed, server/client certificate errors, dataNotAllowed,
                // internationalRoamingOff, backgroundSessionWasDisconnected, …: Google is unreachable.
                return .unreachable
            }
        }
        if ns.domain == NSPOSIXErrorDomain || ns.domain == (kCFErrorDomainCFNetwork as String) { return .unreachable }
        return .http(0)
    }
}

public nonisolated enum DriveUploadOutcome: Equatable, Sendable {
    /// 200 / 201: the file now exists in Drive.
    case completed
    /// 308: continue from this byte offset.
    case resumeAt(Int64)
    /// 404 / 410 on the session URL: start a new session from 0.
    case sessionExpired
    /// 401: refresh the access token and retry.
    case unauthorized
    /// 403 storageQuotaExceeded.
    case quotaExceeded
    /// 408, 429, 5xx, 403 rate limits.
    case retryLater
    /// Anything else; short Chinese message with the status code, never URLs or tokens.
    case failed(String)
}

public nonisolated enum DriveError: Error, Equatable, Sendable {
    case notConfigured, noMember, unreachable, invalidGrant, quotaExceeded, http(Int)

    public var message: String {
        switch self {
        case .notConfigured: "还没配置上传，请在设置里粘贴配置"
        case .noMember: "请先在设置里选择我是谁"
        case .unreachable: "请打开翻墙后重试"
        case .invalidGrant: "请让管理员重新配置"
        case .quotaExceeded: "云盘暂时满了，稍后自动重试"
        case .http(let code): "上传失败（HTTP \(code)）"
        }
    }
}
