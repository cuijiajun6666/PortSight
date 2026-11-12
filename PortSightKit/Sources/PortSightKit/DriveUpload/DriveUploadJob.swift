import Foundation

/// One file in the Drive upload queue. Persisted; holds no secrets except the resumable session URL
/// (the queue file is protected and never logged).
public nonisolated struct DriveUploadJob: Codable, Identifiable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case preparing, waiting, uploading, sent, failed
    }

    /// UUID string.
    public let id: String
    /// PHAsset.localIdentifier.
    public let assetID: String
    public let fileName: String
    public let mimeType: String
    public let folderID: String
    public let member: String
    public let takenAt: Date
    /// 0 until staged.
    public var totalBytes: Int64
    public var sentBytes: Int64
    /// Resumable session (valid about a week).
    public var sessionURL: URL?
    /// Restart the session when older than 6 days.
    public var sessionStartedAt: Date?
    public var state: State
    /// Last user-facing Chinese note.
    public var message: String?
    public var backoff: DriveBackoff
    public let createdAt: Date
    public var finishedAt: Date?

    /// sentBytes / totalBytes, 0 when total is 0.
    public var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(sentBytes) / Double(totalBytes)))
    }

    public init(id: String = UUID().uuidString, assetID: String, fileName: String, mimeType: String, folderID: String,
                member: String, takenAt: Date, createdAt: Date = .now) {
        self.id = id
        self.assetID = assetID
        self.fileName = fileName
        self.mimeType = mimeType
        self.folderID = folderID
        self.member = member
        self.takenAt = takenAt
        self.totalBytes = 0
        self.sentBytes = 0
        self.sessionURL = nil
        self.sessionStartedAt = nil
        self.state = .preparing
        self.message = nil
        self.backoff = DriveBackoff()
        self.createdAt = createdAt
        self.finishedAt = nil
    }
}

/// JSON file persistence for the queue (atomic writes, protected until first unlock on iOS).
public nonisolated struct DriveUploadStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Application Support/DriveUploads/queue.json (directory created on save, excluded from backup).
    public static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("DriveUploads", isDirectory: true)
            .appendingPathComponent("queue.json", isDirectory: false)
    }

    /// [] when missing or corrupt.
    public func load() -> [DriveUploadJob] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([DriveUploadJob].self, from: data)) ?? []
    }

    public func save(_ jobs: [DriveUploadJob]) throws {
        var directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(jobs)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }
}
