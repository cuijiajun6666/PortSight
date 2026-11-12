import Foundation

/// The family app's Google Drive upload configuration (contract §2), pasted by the admin in settings.
/// Stored only in this app's keychain (AfterFirstUnlockThisDeviceOnly); never in source, git, logs or UserDefaults.
public nonisolated struct DriveConfig: Equatable, Sendable {
    public let clientID: String
    public let clientSecret: String
    public let refreshToken: String
    /// 家人名字 → folder id (subfolders of 家人上传).
    public let folders: [String: String]
    /// The family's Immich library, when the admin added one: the 图库 then shows the real photos.
    public let immich: ImmichConfig?

    /// Member names, sorted the way Finder sorts names.
    public var members: [String] {
        folders.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public init(clientID: String, clientSecret: String, refreshToken: String, folders: [String: String],
                immich: ImmichConfig? = nil) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.refreshToken = refreshToken
        self.folders = folders
        self.immich = immich
    }

    /// Never print the secrets (string interpolation, dump, debugger summaries).
    var debugDescriptionSafe: String { "DriveConfig(\(folders.count) 位家人\(immich == nil ? "" : "，含照片库"))" }

    /// Parses the pasted JSON. Tolerates the smart quotes iOS keyboards insert.
    public static func parse(_ text: String) throws -> DriveConfig {
        let cleaned = text
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else { throw DriveConfigError.notJSON }

        func field(_ key: String) throws -> String {
            guard let value = (root[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { throw DriveConfigError.missingField(key) }
            return value
        }
        let clientID = try field("client_id")
        let clientSecret = try field("client_secret")
        let refreshToken = try field("refresh_token")

        guard let rawFolders = root["folders"] as? [String: Any] else { throw DriveConfigError.missingField("folders") }
        guard !rawFolders.isEmpty else { throw DriveConfigError.noFolders }
        var folders: [String: String] = [:]
        for (rawName, rawID) in rawFolders {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw DriveConfigError.missingField("folders 里的家人名字") }
            guard let id = (rawID as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
                throw DriveConfigError.missingField("\(name) 的文件夹 ID")
            }
            folders[name] = id
        }
        let immich = try root["immich"].flatMap { $0 is NSNull ? nil : $0 }.map(ImmichConfig.parse)
        return DriveConfig(clientID: clientID, clientSecret: clientSecret, refreshToken: refreshToken, folders: folders,
                           immich: immich)
    }

    /// Keychain service; account "config"; value = canonical JSON.
    public static let keychainService = "PortSight.drive"
    static let keychainAccount = "config"

    /// Canonical JSON in the contract's key names (sorted keys).
    var canonicalJSON: String? {
        var object: [String: Any] = ["client_id": clientID, "client_secret": clientSecret,
                                     "refresh_token": refreshToken, "folders": folders]
        if let immich { object["immich"] = immich.json }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @MainActor public static func load() -> DriveConfig? {
        guard let text = ServerKeychain.read(service: keychainService, account: keychainAccount) else { return nil }
        return try? parse(text)
    }

    @MainActor @discardableResult public func save() -> Bool {
        guard let json = canonicalJSON else { return false }
        return ServerKeychain.save(json, service: Self.keychainService, account: Self.keychainAccount)
    }

    /// Deletes the keychain item and the "我是谁" choice.
    @MainActor public static func clear() {
        ServerKeychain.delete(service: keychainService, account: keychainAccount)
        DriveMember.current = nil
    }
}

extension DriveConfig: CustomStringConvertible, CustomDebugStringConvertible {
    public nonisolated var description: String { debugDescriptionSafe }
    public nonisolated var debugDescription: String { debugDescriptionSafe }
}

public nonisolated enum DriveConfigError: Error, Equatable, Sendable {
    case notJSON, missingField(String), noFolders, invalidImmich(String)

    public var message: String {
        switch self {
        case .notJSON: "不是有效的 JSON，请整段复制粘贴"
        case .missingField(let name): "缺少 \(name)"
        case .noFolders: "folders 里没有家人"
        case .invalidImmich(let detail): "immich 配置有误：\(detail)"
        }
    }
}

/// "我是谁": the chosen member name (not secret), kept in UserDefaults.
public nonisolated enum DriveMember {
    static let defaultsKey = "PortSight.drive.member"

    public static var current: String? {
        get { UserDefaults.standard.string(forKey: defaultsKey) }
        set {
            if let newValue, !newValue.isEmpty { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
            else { UserDefaults.standard.removeObject(forKey: defaultsKey) }
        }
    }

    /// Folder id for the current member, or nil when no config / no choice / the name is no longer in the config.
    public static func folderID(in config: DriveConfig?) -> String? {
        guard let config, let name = current else { return nil }
        return config.folders[name]
    }
}
