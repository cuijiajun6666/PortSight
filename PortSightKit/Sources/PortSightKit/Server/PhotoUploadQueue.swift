//
//  PhotoUploadQueue.swift
//  PortSight
//
//  Photos and folders dropped on the upload sheet wait here for Immich on the Mac mini.
//  Folders are expanded to the photos and videos inside them. Nothing is sent yet: until the Mac mini and
//  its Immich address are set up, items stay queued. The upload itself (Immich's asset API over Tailscale)
//  is added with the real connection.
//

import Foundation
import Combine
import UniformTypeIdentifiers

public struct UploadItem: Identifiable, Hashable {
    public enum State: Hashable {
        case waiting, uploading(Double), done, failed(String)
    }

    public let url: URL
    public let name: String
    public let bytes: Int64
    public let isVideo: Bool
    public var state: State
    public var id: URL { url }
}

@MainActor
public final class PhotoUploadQueue: ObservableObject {
    @Published public private(set) var items: [UploadItem] = []
    @Published public var message: String?
    /// Non-media files seen in drops, counted once each however often the same folder is dropped.
    @Published private var skippedFiles: Set<URL> = []

    public var skipped: Int { skippedFiles.count }

    public init() {}

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    public var photoCount: Int { items.filter { !$0.isVideo }.count }
    public var videoCount: Int { items.filter(\.isVideo).count }
    public var waitingCount: Int { items.filter { $0.state == .waiting }.count }

    /// Adds dropped or chosen files; folders are searched recursively. Returns how many media files were added.
    @discardableResult
    public func add(_ urls: [URL]) -> Int {
        var found: [UploadItem] = []
        var ignored: Set<URL> = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            found += Self.mediaFiles(at: url, ignored: &ignored)
        }
        var known = Set(items.map(\.url))
        let fresh = found.filter { known.insert($0.url).inserted }
        items.append(contentsOf: fresh)
        skippedFiles.formUnion(ignored)
        if !fresh.isEmpty {
            message = nil
        } else {
            message = found.isEmpty ? "没有找到照片或视频" : "这些文件已经在队列里了"
        }
        return fresh.count
    }

    public func remove(_ item: UploadItem) {
        items.removeAll { $0.id == item.id }
        if items.isEmpty { clear() }
    }

    public func clear() {
        items.removeAll()
        skippedFiles.removeAll()
        message = nil
    }

    /// Photos dragged from the Photos app arrive as file promises, not file URLs: their data is copied
    /// here first. Call from the provider's callback, before it deletes its temporary file.
    public nonisolated static func keepImportedCopy(of temporary: URL, suggestedName: String?) -> URL? {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PortSight/UploadImports/\(UUID().uuidString)", isDirectory: true)
        let ext = temporary.pathExtension
        var name = suggestedName ?? temporary.deletingPathExtension().lastPathComponent
        if !ext.isEmpty, (name as NSString).pathExtension.isEmpty { name += "." + ext }
        let target = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: temporary, to: target)
            return target
        } catch {
            return nil
        }
    }

    /// Demo mode: the queue never uploads. With a configured Immich server this starts the background upload.
    public func start() {
        guard !DemoPortfolioData.enabled else {
            message = "会在后台上传这些文件"
            return
        }
        message = "还没有配置 Immich 地址"
    }

    private static func mediaFiles(at url: URL, ignored: inout Set<URL>) -> [UploadItem] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else {
            if let item = item(for: url) { return [item] }
            ignored.insert(url)
            return []
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentTypeKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [UploadItem] = []
        for case let file as URL in walker {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            if let item = item(for: file) { found.append(item) } else { ignored.insert(file) }
        }
        return found
    }

    private static func item(for url: URL) -> UploadItem? {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
        guard let type, type.conforms(to: .image) || type.conforms(to: .movie) else { return nil }
        return UploadItem(url: url, name: url.lastPathComponent, bytes: Int64(values?.fileSize ?? 0),
                          isVideo: type.conforms(to: .movie), state: .waiting)
    }
}
