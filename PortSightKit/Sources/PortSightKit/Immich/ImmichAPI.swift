//
//  ImmichAPI.swift
//  PortSightKit
//
//  Read-only access to the family's Immich library on the Mac mini (Immich v3, checked against v3.3.6), reached
//  over the Mac mini's public HTTPS address so a phone with only its proxy app on can see the photos. The key is a
//  read-only Immich API key for this phone (asset.read, asset.view, asset.download ...), pasted with the Drive
//  configuration. It only ever travels in the x-api-key header: never in a URL, a log or a description.
//  Pure request builders and response parsers here, like DriveAPI; the networking is in FamilyLibrary and the app.
//

import Foundation

/// Where the family's Immich is and the read-only key this phone uses (the `immich` part of the pasted config).
public nonisolated struct ImmichConfig: Equatable, Sendable {
    /// https://host[:port], without a trailing slash or /api.
    public let url: URL
    public let apiKey: String

    public init(url: URL, apiKey: String) {
        self.url = url
        self.apiKey = apiKey
    }

    /// Reads {"url": "https://…", "api_key": "…"}. The address must be https and must not end in /api.
    static func parse(_ object: Any) throws -> ImmichConfig {
        guard let root = object as? [String: Any] else { throw DriveConfigError.invalidImmich("应该是一个对象") }
        var address = ((root["url"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        while address.hasSuffix("/") { address.removeLast() }
        guard !address.isEmpty else { throw DriveConfigError.invalidImmich("缺少 url") }
        guard let url = URL(string: address), url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.query == nil, url.fragment == nil, url.user == nil else {
            throw DriveConfigError.invalidImmich("url 只能是 https:// 开头的地址")
        }
        guard !url.path.lowercased().hasSuffix("/api") else {
            throw DriveConfigError.invalidImmich("url 只写到域名，不要加 /api")
        }
        let key = ((root["api_key"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DriveConfigError.invalidImmich("缺少 api_key") }
        guard !key.contains(where: { $0.isWhitespace }) else { throw DriveConfigError.invalidImmich("api_key 里不能有空格") }
        return ImmichConfig(url: url, apiKey: key)
    }

    var json: [String: Any] { ["url": url.absoluteString, "api_key": apiKey] }

    /// The host only, for settings and descriptions.
    public var host: String { url.host ?? "" }
}

extension ImmichConfig: CustomStringConvertible, CustomDebugStringConvertible {
    public nonisolated var description: String { "ImmichConfig(\(host))" }
    public nonisolated var debugDescription: String { description }
}

/// One month of the library (Immich's time bucket), as the server counts it: by the photographer's local month.
public nonisolated struct ImmichBucket: Equatable, Sendable {
    /// "2026-10-01"
    public let timeBucket: String
    public let count: Int

    public var year: Int? { Int(timeBucket.prefix(4)) }
    public var month: Int? {
        let parts = timeBucket.split(separator: "-")
        return parts.count >= 2 ? Int(parts[1]) : nil
    }
}

/// One photo or video from a time bucket.
public nonisolated struct ImmichAsset: Equatable, Sendable {
    public let id: String
    public let isImage: Bool
    /// Width / height (orientation-corrected); 1 while the server has not processed the file yet.
    public let ratio: Double
    /// The real moment it was taken.
    public let takenAtUTC: Date
    /// Hours east of UTC where it was taken (0 when unknown).
    public let localOffsetHours: Double
    /// Milliseconds; nil for still pictures.
    public let durationMs: Int?
    /// The hidden video of a Live Photo.
    public let livePhotoVideoID: String?
    public let city: String?
}

public nonisolated enum ImmichImageSize: String, Sendable {
    /// About 250 px (WebP by default): grid tiles and cards.
    case thumbnail
    /// About 1440 px (JPEG by default): the full-screen viewer.
    case preview
}

public nonisolated enum ImmichError: Error, Equatable, Sendable {
    /// 401: the key is wrong or was deleted.
    case unauthorized
    /// 403: the key lacks a permission.
    case forbidden
    case http(Int)
    case badResponse
    /// No answer (no network, proxy off, server down).
    case unreachable

    public var message: String {
        switch self {
        case .unauthorized: "照片库的钥匙无效，请让管理员重新发一份配置"
        case .forbidden: "照片库的钥匙权限不够，请让管理员检查"
        case .http(let code): "照片库出错了（\(code)），稍后再试"
        case .badResponse: "照片库返回的内容看不懂，可能需要更新 App"
        case .unreachable: "连不上照片库，请确认已打开翻墙"
        }
    }
}

public nonisolated enum ImmichAPI {
    // MARK: Requests

    static func request(_ config: ImmichConfig, _ path: String, query: [URLQueryItem] = [],
                        accept: String = "application/json") -> URLRequest {
        var components = URLComponents(url: config.url, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.path = config.url.path + "/api" + path
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url ?? config.url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return request
    }

    /// The months of the main timeline (not archived, not trashed), oldest first.
    public static func bucketsRequest(_ config: ImmichConfig) -> URLRequest {
        request(config, "/timeline/buckets", query: [URLQueryItem(name: "visibility", value: "timeline"),
                                                    URLQueryItem(name: "order", value: "asc")])
    }

    /// One month's assets, oldest first.
    public static func bucketRequest(_ config: ImmichConfig, timeBucket: String) -> URLRequest {
        request(config, "/timeline/bucket", query: [URLQueryItem(name: "timeBucket", value: timeBucket + "T00:00:00.000Z"),
                                                   URLQueryItem(name: "visibility", value: "timeline"),
                                                   URLQueryItem(name: "order", value: "asc")])
    }

    /// A picture of the asset (a frame for videos). Thumbnails rarely change, so they may come from the cache.
    public static func imageRequest(_ config: ImmichConfig, assetID: String, size: ImmichImageSize) -> URLRequest {
        var request = request(config, "/assets/\(pathComponent(assetID))/thumbnail",
                              query: [URLQueryItem(name: "size", value: size.rawValue)], accept: "image/*")
        request.cachePolicy = .returnCacheDataElseLoad
        return request
    }

    /// Where AVPlayer streams a video from (with Range requests). Send `headers(config)` with it.
    public static func playbackURL(_ config: ImmichConfig, assetID: String) -> URL? {
        request(config, "/assets/\(pathComponent(assetID))/video/playback", accept: "video/*").url
    }

    /// The header that carries the key, for players that take headers instead of a URLRequest.
    public static func headers(_ config: ImmichConfig) -> [String: String] { ["x-api-key": config.apiKey] }

    /// Asset ids are UUIDs; anything else is dropped so it cannot change the path.
    static func pathComponent(_ id: String) -> String {
        String(id.filter { $0.isASCII && ($0.isHexDigit || $0 == "-") })
    }

    // MARK: Responses

    static func check(status: Int) throws {
        switch status {
        case 200..<300: return
        case 401: throw ImmichError.unauthorized
        case 403: throw ImmichError.forbidden
        default: throw ImmichError.http(status)
        }
    }

    private struct BucketDTO: Decodable {
        let timeBucket: String
        let count: Int
    }

    public static func parseBuckets(status: Int, body: Data) throws -> [ImmichBucket] {
        try check(status: status)
        guard let items = try? JSONDecoder().decode([BucketDTO].self, from: body) else { throw ImmichError.badResponse }
        return items.filter { $0.count > 0 }.map { ImmichBucket(timeBucket: $0.timeBucket, count: $0.count) }
    }

    /// TimeBucketAssetResponseDto: parallel arrays, one index per asset. Unknown keys are ignored.
    private struct BucketAssetsDTO: Decodable {
        let id: [String]
        let isImage: [Bool]
        let ratio: [Double]
        let fileCreatedAt: [String]
        let localOffsetHours: [Double]
        let duration: [Int?]
        let livePhotoVideoId: [String?]
        let city: [String?]?
    }

    public static func parseBucket(status: Int, body: Data) throws -> [ImmichAsset] {
        try check(status: status)
        guard let dto = try? JSONDecoder().decode(BucketAssetsDTO.self, from: body) else { throw ImmichError.badResponse }
        let count = dto.id.count
        guard dto.isImage.count == count, dto.ratio.count == count, dto.fileCreatedAt.count == count,
              dto.localOffsetHours.count == count, dto.duration.count == count, dto.livePhotoVideoId.count == count,
              dto.city.map({ $0.count == count }) ?? true else { throw ImmichError.badResponse }
        var assets: [ImmichAsset] = []
        assets.reserveCapacity(count)
        for index in 0..<count {
            guard let taken = date(dto.fileCreatedAt[index]) else { throw ImmichError.badResponse }
            assets.append(ImmichAsset(id: dto.id[index], isImage: dto.isImage[index],
                                      ratio: dto.ratio[index] > 0 ? dto.ratio[index] : 1,
                                      takenAtUTC: taken, localOffsetHours: dto.localOffsetHours[index],
                                      durationMs: dto.duration[index], livePhotoVideoID: dto.livePhotoVideoId[index],
                                      city: dto.city?[index].flatMap { $0.isEmpty ? nil : $0 }))
        }
        return assets
    }

    /// Immich dates come as "2026-10-11T14:30:00", "2026-10-28T10:42:10.517", "2026-10-19T00:15:03.842Z" or
    /// "...+00:00": 0-6 fractional digits and an optional zone. No zone means UTC.
    static func date(_ text: String) -> Date? {
        let scalars = Array(text.utf8)
        func number(_ from: Int, _ length: Int) -> Int? {
            guard from + length <= scalars.count else { return nil }
            var value = 0
            for byte in scalars[from..<(from + length)] {
                guard byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            return value
        }
        guard scalars.count >= 19, scalars[4] == 45, scalars[7] == 45, scalars[10] == 84 || scalars[10] == 32,
              scalars[13] == 58, scalars[16] == 58,
              let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
              let hour = number(11, 2), let minute = number(14, 2), let second = number(17, 2) else { return nil }
        var index = 19
        var fraction = 0.0
        if index < scalars.count, scalars[index] == 46 {
            index += 1
            var scale = 0.1
            while index < scalars.count, scalars[index] >= 48, scalars[index] <= 57 {
                fraction += Double(scalars[index] - 48) * scale
                scale /= 10
                index += 1
            }
        }
        var offsetSeconds = 0
        if index < scalars.count {
            switch scalars[index] {
            case 90: index += 1                                    // Z
            case 43, 45:                                           // + / -
                let sign = scalars[index] == 45 ? -1 : 1
                guard let hours = number(index + 1, 2) else { return nil }
                var minutes = 0
                if index + 3 < scalars.count {
                    let colon = scalars[index + 3] == 58 ? 1 : 0
                    minutes = number(index + 3 + colon, 2) ?? 0
                    index += 3 + colon + 2
                } else {
                    index += 3
                }
                offsetSeconds = sign * (hours * 3600 + minutes * 60)
            default: return nil
            }
        }
        guard index >= scalars.count else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let base = calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                            hour: hour, minute: minute, second: second)) else { return nil }
        return base.addingTimeInterval(fraction - Double(offsetSeconds))
    }
}
