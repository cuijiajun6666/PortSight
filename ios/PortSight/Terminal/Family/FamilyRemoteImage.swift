//
//  FamilyRemoteImage.swift
//  PortSight
//
//  Pictures and videos from the family's Immich library (FamilyLibrary). Pictures are kept decoded in memory
//  and as files in Caches/FamilyPhotoCache, so anything seen once comes back without the network; a tile that
//  scrolls away before its picture arrives cancels the download (the proxy link from China is slow). The key
//  only travels in the x-api-key header (ImmichAPI); it is never put in a URL, logged or written to disk: the
//  disk cache is filled by hand under the bare address, because URLCache would store the request's headers.
//

import SwiftUI
import AVKit
import UniformTypeIdentifiers
import PortSightKit

@MainActor final class FamilyImageStore {
    static let shared = FamilyImageStore()

    private final class Load {
        let task: Task<UIImage?, Never>
        var waiters = 0
        init(task: Task<UIImage?, Never>) { self.task = task }
    }

    private let memory = NSCache<NSString, UIImage>()
    private let urlCache: URLCache
    private let session: URLSession
    private var loads: [String: Load] = [:]

    private init() {
        memory.totalCostLimit = 160 * 1024 * 1024
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        // An earlier build let URLCache write this folder itself, keyed requests (and so the key) included.
        if let old = caches?.appendingPathComponent("FamilyPhotos", isDirectory: true) {
            try? FileManager.default.removeItem(at: old)
        }
        urlCache = URLCache(memoryCapacity: 0, diskCapacity: 600 * 1024 * 1024,
                            directory: caches?.appendingPathComponent("FamilyPhotoCache", isDirectory: true))
        // Nothing of the session itself is kept: no cache (see above), no cookies or credentials on disk.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.httpMaximumConnectionsPerHost = 6
        // Never the demo mode's offline guard: these requests are the family's own server.
        configuration.protocolClasses = configuration.protocolClasses?.filter {
            ObjectIdentifier($0) != ObjectIdentifier(DemoOfflineProtocol.self)
        }
        session = URLSession(configuration: configuration)
    }

    private func key(_ id: String, _ size: ImmichImageSize) -> String { id + "|" + size.rawValue }

    /// Already decoded, for the first frame of a view.
    func cached(_ id: String, _ size: ImmichImageSize) -> UIImage? {
        memory.object(forKey: key(id, size) as NSString)
    }

    /// The picture, from memory, the disk cache or Immich. nil when it cannot be had (offline, not generated yet).
    func image(_ id: String, _ size: ImmichImageSize, config: ImmichConfig) async -> UIImage? {
        let key = key(id, size)
        if let image = memory.object(forKey: key as NSString) { return image }
        let load: Load
        if let existing = loads[key] {
            load = existing
        } else {
            let request = ImmichAPI.imageRequest(config, assetID: id, size: size)
            guard let url = request.url else { return nil }
            // The cache's own key is the bare address: it never sees the x-api-key header.
            let cacheKey = URLRequest(url: url)
            let session = session, urlCache = urlCache
            load = Load(task: Task.detached(priority: size == .preview ? .userInitiated : .utility) {
                if let hit = urlCache.cachedResponse(for: cacheKey), let image = UIImage(data: hit.data) {
                    return await image.byPreparingForDisplay() ?? image
                }
                guard let (data, response) = try? await session.data(for: request),
                      let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let image = UIImage(data: data) else { return nil }
                urlCache.storeCachedResponse(CachedURLResponse(response: http, data: data, userInfo: nil, storagePolicy: .allowed),
                                             for: cacheKey)
                return await image.byPreparingForDisplay() ?? image
            })
            loads[key] = load
        }
        load.waiters += 1
        let image = await withTaskCancellationHandler {
            await load.task.value
        } onCancel: {
            Task { @MainActor in self.release(key, load) }
        }
        if !Task.isCancelled { release(key, load) }
        if let image {
            let pixels = image.size.width * image.scale * image.size.height * image.scale
            memory.setObject(image, forKey: key as NSString, cost: Int(pixels * 4))
        }
        return image
    }

    /// The last view waiting for a picture went away: stop downloading it.
    private func release(_ key: String, _ load: Load) {
        load.waiters -= 1
        guard load.waiters <= 0 else { return }
        if loads[key] === load { loads[key] = nil }
        load.task.cancel()
    }

    /// After the configuration is cleared: the family's pictures do not stay on the phone.
    func clear() {
        for load in loads.values { load.task.cancel() }
        loads = [:]
        memory.removeAllObjects()
        urlCache.removeAllCachedResponses()
    }
}

/// An Immich picture: a cropped thumbnail in tiles, the whole preview in the viewer (the thumbnail stands in
/// until the preview arrives, so the viewer never opens on an empty frame).
struct FamilyRemoteImage: View {
    let photo: FamilyPhoto
    var fit = false
    @State private var image: UIImage?
    /// The viewer's picture could not be had (offline, refused, not generated yet): say so instead of spinning.
    @State private var failed = false
    @State private var attempt = 0

    private var size: ImmichImageSize { fit ? .preview : .thumbnail }

    var body: some View {
        let store = FamilyImageStore.shared
        let shown = image ?? store.cached(photo.id, size) ?? (fit ? store.cached(photo.id, .thumbnail) : nil)
        ZStack {
            if let shown {
                Image(uiImage: shown)
                    .resizable()
                    .aspectRatio(contentMode: fit ? .fit : .fill)
            } else if fit {
                if failed {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
                        Text("图片暂时打不开").font(.subheadline).foregroundStyle(.secondary)
                        Button("重试") { attempt += 1 }
                            .buttonStyle(.glass)
                    }
                } else {
                    ProgressView()
                }
            } else {
                Rectangle().fill(Color(.secondarySystemFill))
            }
        }
        .task(id: "\(photo.id)|\(size.rawValue)|\(attempt)") {
            failed = false
            guard let config = FamilyLibrary.shared.connection else { return }
            if fit, store.cached(photo.id, .preview) == nil, store.cached(photo.id, .thumbnail) == nil {
                image = await store.image(photo.id, .thumbnail, config: config)
            }
            if let loaded = await store.image(photo.id, size, config: config) { image = loaded }
            if !Task.isCancelled, image == nil, store.cached(photo.id, size) == nil, store.cached(photo.id, .thumbnail) == nil {
                failed = true
            }
        }
    }
}

/// An Immich photo for the share sheet: its preview picture, fetched when the share happens.
nonisolated struct FamilySharedPhoto: Transferable {
    let id: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { item in
            guard let config = await FamilyLibrary.shared.connection,
                  let image = await FamilyImageStore.shared.image(item.id, .preview, config: config),
                  let data = image.jpegData(compressionQuality: 0.9) else { throw CocoaError(.fileReadUnknown) }
            return data
        }
    }
}

/// A video from Immich in the viewer: its preview picture with a play button; playing streams it (AVPlayer
/// sends the key as a header). Nothing downloads until play is tapped.
struct FamilyRemoteVideo: View {
    let photo: FamilyPhoto
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else {
                Button(action: play) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 30))
                        .frame(width: 76, height: 76)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("播放视频")
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private func play() {
        guard let config = FamilyLibrary.shared.connection,
              let url = ImmichAPI.playbackURL(config, assetID: photo.id) else { return }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ImmichAPI.headers(config)])
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        self.player = player
        player.play()
    }
}
