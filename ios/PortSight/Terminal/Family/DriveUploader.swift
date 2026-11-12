//
//  DriveUploader.swift
//  PortSight
//
//  家人版 → Google 云盘直传 (Docs: Drive upload contract, 2026-11-09). The app exchanges the pasted refresh token for
//  an access token (memory only), opens a resumable upload session in the member's folder, then sends the
//  original file in 8 MB chunks through a background URLSession, so uploads go on while the app is in the
//  background. After a break it first asks Drive how far the upload got (PUT "bytes */total") and goes on from
//  there; it never starts an interrupted upload again from 0. The Mac mini moves the files out of Drive.
//  The app only uploads: it never lists or deletes anything in Drive, and never deletes photos.
//  Nothing here prints or logs tokens, secrets or upload-session URLs.
//

import Foundation
import Observation
import Photos
import UIKit
import UniformTypeIdentifiers
import PortSightKit

@MainActor @Observable final class DriveUploader {
    static let shared = DriveUploader()
    static let sessionIdentifier = "PortSight.drive.upload"
    /// Set after invalid_grant until a new configuration is saved (not secret).
    private static let needsConfigKey = "PortSight.drive.needsConfig"
    /// Set once this install has removed a Drive configuration left in the keychain by an earlier install
    /// (keychain items outlive deleting the app; UserDefaults do not).
    private static let installedKey = "PortSight.drive.installed"
    private static let maxUploads = 2
    private static let maxStaging = 2
    /// Staged copies waiting or uploading, plus copies being made: the rest stay in the photo library until then.
    private static let maxStagedAhead = maxUploads + maxStaging

    /// The upload queue, persisted after every change.
    private(set) var jobs: [DriveUploadJob]
    /// Latest problem that affects every upload (nil when fine).
    private(set) var status: DriveError?
    /// From application(_:handleEventsForBackgroundURLSession:completionHandler:); called on the main thread once
    /// the background session has delivered all its events.
    var backgroundCompletionHandler: (() -> Void)?

    @ObservationIgnored private let store = DriveUploadStore(url: DriveUploadStore.defaultURL)
    @ObservationIgnored private let delegate = DriveSessionDelegate()
    @ObservationIgnored private var backgroundSession: URLSession?
    /// Token exchange and the initiate POST: small requests made while the app runs.
    @ObservationIgnored private let api: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
    @ObservationIgnored private var token: DriveAccessToken?
    @ObservationIgnored private var tokenTask: Task<DriveAccessToken, Error>?
    /// Jobs with a live background task, a running initiate, or a pending in-app retry.
    @ObservationIgnored private var inFlight: Set<String> = []
    /// The one background task each job is waiting for; results from any other task of that job are stale.
    @ObservationIgnored private var currentTask: [String: Int] = [:]
    @ObservationIgnored private var staging: Set<String> = []
    @ObservationIgnored private var retryTimers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var reconciled = false
    @ObservationIgnored private var reconciling = false
    /// False while queue.json exists but cannot be read yet (the app was launched before the first unlock):
    /// until it has been read nothing is reconciled, cancelled or saved, so the saved queue is never overwritten.
    @ObservationIgnored private var queueLoaded = false
    /// Jobs whose session was dropped after a 401; their backoff is kept until a chunk gets through.
    @ObservationIgnored private var restartedAfter401: Set<String> = []

    private var needsConfig: Bool {
        get { UserDefaults.standard.bool(forKey: Self.needsConfigKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.needsConfigKey) }
    }

    private init() {
        jobs = []
        if UserDefaults.standard.bool(forKey: Self.needsConfigKey) { status = .invalidGrant }
        forgetPreviousInstall()
        loadQueue()
    }

    /// A reinstalled app starts unconfigured: the keychain keeps the old client secret and refresh token after the
    /// app is deleted, so remove them on the first launch of this install (only once the keychain and
    /// UserDefaults can be read, i.e. after the first unlock).
    private func forgetPreviousInstall() {
        let defaults = UserDefaults.standard
        guard UIApplication.shared.isProtectedDataAvailable, !defaults.bool(forKey: Self.installedKey) else { return }
        DriveConfig.clear()
        defaults.set(true, forKey: Self.installedKey)
    }

    private func loadQueue() {
        guard !queueLoaded else { return }
        let url = store.url
        guard FileManager.default.fileExists(atPath: url.path) else {
            jobs = []
            queueLoaded = true
            return
        }
        // Protected until the first unlock: leave everything as it is and read it on the next resume().
        guard let data = try? Data(contentsOf: url) else { return }
        let loaded = store.load()
        if loaded.isEmpty, ((try? JSONSerialization.jsonObject(with: data)) as? [Any])?.isEmpty != true {
            // Readable but not decodable (e.g. written by another version): keep a copy, start a new queue.
            let copy = url.deletingLastPathComponent().appendingPathComponent("queue.unreadable.json")
            try? FileManager.default.removeItem(at: copy)
            try? FileManager.default.copyItem(at: url, to: copy)
        }
        jobs = loaded
        queueLoaded = true
    }

    // MARK: Public

    /// True when there is no configuration or no "我是谁" yet.
    static var needsSetup: Bool { DriveMember.folderID(in: DriveConfig.load()) == nil }

    /// Adds the originals of these photo-library assets to the queue. Returns a short note for the toast.
    func enqueue(assetIDs: [String]) async -> String {
        guard !assetIDs.isEmpty else { return "没有选中照片" }
        guard let config = DriveConfig.load() else { return DriveError.notConfigured.message }
        guard let member = DriveMember.current, let folderID = DriveMember.folderID(in: config) else {
            return DriveError.noMember.message
        }
        if needsConfig { return DriveError.invalidGrant.message }
        loadQueue()
        guard queueLoaded else { return "请解锁 iPhone 后再试" }

        var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if authorization == .notDetermined {
            authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard authorization == .authorized || authorization == .limited else {
            return "没有照片权限，请在系统设置里允许 PortSight 访问照片"
        }

        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        var added = 0, already = 0
        fetched.enumerateObjects { asset, _, _ in
            let takenAt = asset.creationDate ?? asset.modificationDate ?? .now
            for resource in Self.originals(of: asset) {
                let fileName = DriveFileName.make(takenAt: takenAt, assetID: asset.localIdentifier,
                                                  originalName: resource.originalFilename)
                if let existing = self.jobs.first(where: { $0.fileName == fileName && $0.folderID == folderID }) {
                    guard existing.state == .failed else { already += 1; continue }
                    self.discard(existing.id)
                }
                let mimeType = UTType(resource.uniformTypeIdentifier)?.preferredMIMEType ?? "application/octet-stream"
                self.jobs.append(DriveUploadJob(assetID: asset.localIdentifier, fileName: fileName, mimeType: mimeType,
                                                folderID: folderID, member: member, takenAt: takenAt))
                added += 1
            }
        }
        persist()
        pump()

        let unreadable = assetIDs.count - fetched.count
        var note: String
        if added > 0 {
            note = "已加入 \(added) 个文件，正在后台上传"
        } else if already > 0 {
            note = "这些照片已经在上传列表里"
        } else {
            note = "没有可上传的原图"
        }
        if unreadable > 0 { note += "，\(unreadable) 项读不到（请允许访问全部照片）" }
        return note
    }

    /// A failed job goes back into the queue.
    func retry(_ job: DriveUploadJob) {
        guard let index = index(job.id), jobs[index].state == .failed else { return }
        if isStaged(jobs[index]) {
            jobs[index].state = .waiting
        } else {
            Self.restage(&jobs[index])
        }
        jobs[index].message = nil
        jobs[index].backoff.reset()
        persist()
        pump()
    }

    /// 刷新: try now instead of waiting out the backoff (e.g. right after turning the VPN on); failed jobs go back
    /// into the queue too. After invalid_grant nothing is sent until a new configuration is saved.
    func refreshNow() async -> String {
        resume()
        guard queueLoaded else { return "请解锁 iPhone 后再试" }
        guard !needsConfig else { return DriveError.invalidGrant.message }
        clearTransientStatus()
        for job in jobs where job.state == .failed { retry(job) }
        for index in jobs.indices where jobs[index].state == .waiting || jobs[index].state == .uploading {
            jobs[index].backoff.reset()
        }
        persist()
        // Waits in the app (no session yet): start them now.
        for (id, timer) in retryTimers {
            timer.cancel()
            inFlight.remove(id)
        }
        retryTimers.removeAll()
        // Waits in the background session (a status PUT with earliestBeginDate): ask now. The new task becomes the
        // job's current task first, so the cancelled delayed one is ignored when its completion arrives.
        let now = Date.now
        for task in await connect().allTasks {
            guard let id = task.taskDescription, let begin = task.earliestBeginDate, begin > now,
                  currentTask[id] == task.taskIdentifier,
                  jobs.first(where: { $0.id == id })?.state == .waiting else { continue }
            schedule(id, .status)
            task.cancel()
        }
        pump()
        let open = jobs.filter { $0.state != .sent && $0.state != .failed }.count
        return open > 0 ? "正在重试 \(open) 个文件" : "没有需要上传的文件"
    }

    /// On launch, when the app becomes active and when iOS wakes the app for background-session events:
    /// reconnects to the background session, matches its tasks to the queue and continues.
    func resume() {
        forgetPreviousInstall()
        loadQueue()
        _ = connect()
        guard queueLoaded else { return }
        if reconciled { pump() } else { reconcile() }
    }

    /// After a new configuration was saved.
    func configurationChanged() {
        needsConfig = false
        token = nil
        status = nil
        pump()
    }

    /// 清除配置: removes the keychain item and "我是谁", stops every upload and drops unfinished jobs (and their
    /// staged copies). `.sent` history stays. Nothing in Drive or in the photo library is touched.
    func clearConfiguration() {
        DriveConfig.clear()
        needsConfig = false
        token = nil
        tokenTask?.cancel()
        tokenTask = nil
        status = nil
        cancelEverything()
        for job in jobs where job.state != .sent { DriveFiles.removeTemporaryFiles(of: job.id) }
        jobs.removeAll { $0.state != .sent }
        persist()
    }

    // MARK: Queue

    private func index(_ id: String) -> Int? { jobs.firstIndex { $0.id == id } }

    private func persist() {
        guard queueLoaded else { return }
        try? store.save(jobs)
    }

    /// The staged copy is complete: it has exactly the size recorded when staging finished (never 0 bytes).
    private func isStaged(_ job: DriveUploadJob) -> Bool {
        guard job.totalBytes > 0 else { return false }
        let attributes = try? FileManager.default.attributesOfItem(atPath: DriveFiles.staged(job.id).path)
        return (attributes?[.size] as? NSNumber)?.int64Value == job.totalBytes
    }

    /// Drops a missing or incomplete staged copy (and the session that belonged to it); the original is copied again.
    private static func restage(_ job: inout DriveUploadJob) {
        DriveFiles.removeTemporaryFiles(of: job.id)
        job.totalBytes = 0
        job.sentBytes = 0
        job.sessionURL = nil
        job.sessionStartedAt = nil
        job.state = .preparing
    }

    private func update(_ id: String, _ change: (inout DriveUploadJob) -> Void) {
        guard let index = index(id) else { return }
        change(&jobs[index])
        persist()
    }

    private func discard(_ id: String) {
        restartedAfter401.remove(id)
        retryTimers.removeValue(forKey: id)?.cancel()
        inFlight.remove(id)
        currentTask[id] = nil
        DriveFiles.removeTemporaryFiles(of: id)
        jobs.removeAll { $0.id == id }
    }

    /// Stages what needs staging and starts uploads, at most `maxUploads` at a time.
    private func pump() {
        guard queueLoaded else { return }
        // Copy originals only a few ahead of the uploads, so picking many large videos does not fill the iPhone.
        var ahead = jobs.filter { $0.state == .waiting || $0.state == .uploading }.count + staging.count
        for job in jobs where job.state == .preparing && !staging.contains(job.id) {
            guard staging.count < Self.maxStaging, ahead < Self.maxStagedAhead else { break }
            ahead += 1
            stage(job.id)
        }
        guard reconciled else { resume(); return }
        guard !needsConfig else { return }
        let unfinished = Set(jobs.filter { $0.state == .waiting || $0.state == .uploading }.map(\.id))
        var busy = inFlight.intersection(unfinished).count
        for job in jobs where unfinished.contains(job.id) && !inFlight.contains(job.id) {
            // A job that failed (backoff running) is retried only while the app is in the foreground.
            if job.backoff.attempt > 0 && !inForeground { continue }
            guard busy < Self.maxUploads else { break }
            busy += 1
            step(job.id)
        }
    }

    /// The next request for a job that has no live task: a new session, or a status PUT to learn the offset.
    private func step(_ id: String) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        guard isStaged(job) else {
            update(id) { Self.restage(&$0) }
            pump()
            return
        }
        if job.sessionURL != nil {
            // Never restart an interrupted upload from 0: ask Drive how far it got first, however old the session
            // is (the last chunk may have arrived). An expired session answers 404/410 and is started again.
            schedule(id, .status)
        } else {
            inFlight.insert(id)
            Task {
                // A session start during a background wake must finish before iOS suspends the app again.
                let time = BackgroundTime("PortSight.drive.initiate")
                await initiate(id)
                time.end()
            }
        }
    }

    // MARK: Staging (the original resource, copied out of the photo library)

    /// Photo → `.photo`; Live Photo → `.photo` + `.pairedVideo` (same name prefix); video → `.video`.
    /// The edited/full-size renditions are used only when the original resource is missing.
    nonisolated static func originals(of asset: PHAsset) -> [PHAssetResource] {
        let resources = PHAssetResource.assetResources(for: asset)
        func first(_ type: PHAssetResourceType) -> PHAssetResource? { resources.first { $0.type == type } }
        switch asset.mediaType {
        case .image:
            var picked = [first(.photo) ?? first(.fullSizePhoto)].compactMap { $0 }
            if asset.mediaSubtypes.contains(.photoLive), let video = first(.pairedVideo) ?? first(.fullSizePairedVideo) {
                picked.append(video)
            }
            return picked
        case .video:
            return [first(.video) ?? first(.fullSizeVideo)].compactMap { $0 }
        default:
            return []
        }
    }

    private func stage(_ id: String) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [job.assetID], options: nil).firstObject,
              let resource = Self.originals(of: asset).first(where: {
                  DriveFileName.make(takenAt: job.takenAt, assetID: asset.localIdentifier, originalName: $0.originalFilename) == job.fileName
                      || job.fileName.hasSuffix("_" + $0.originalFilename)
              })
        else {
            update(id) { $0.state = .failed; $0.message = "相册里找不到这个文件了" }
            return
        }
        staging.insert(id)
        Task {
            let time = BackgroundTime("PortSight.drive.stage")
            defer { time.end() }
            let result: Result<Int64, Error>
            do {
                result = .success(try await DriveFiles.writeResource(resource, to: DriveFiles.staged(id)))
            } catch {
                result = .failure(error)
            }
            staging.remove(id)
            guard index(id) != nil else { DriveFiles.removeTemporaryFiles(of: id); return }
            switch result {
            case .success(let size):
                update(id) { $0.totalBytes = size; $0.state = .waiting; $0.message = nil }
            case .failure(let error) where error is DriveFiles.Stalled:
                // No data for a while (e.g. iCloud stalled, or the app was suspended): copy it again later.
                update(id) { Self.restage(&$0); $0.message = "等待从 iCloud 读取原图" }
            case .failure:
                update(id) { $0.state = .failed; $0.message = "读取原图失败，请检查网络后重试" }
            }
            pump()
        }
    }

    // MARK: Token and session start (ephemeral session)

    private func accessToken(_ config: DriveConfig) async throws -> DriveAccessToken {
        if let token, token.isValid() { return token }
        if let tokenTask { return try await tokenTask.value }
        let api = api
        let task = Task { () throws -> DriveAccessToken in
            let (data, response) = try await api.data(for: DriveAPI.tokenRequest(config))
            return try DriveAPI.parseToken(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        }
        tokenTask = task
        defer { tokenTask = nil }
        let fresh = try await task.value
        token = fresh
        return fresh
    }

    private func initiate(_ id: String, retriedAfter401: Bool = false) async {
        guard let job = jobs.first(where: { $0.id == id }), !needsConfig else { inFlight.remove(id); return }
        guard job.totalBytes > 0 else {
            // Never open a session for an empty file: the original has not been copied completely.
            inFlight.remove(id)
            update(id) { Self.restage(&$0) }
            pump()
            return
        }
        guard let config = DriveConfig.load() else {
            inFlight.remove(id)
            status = .notConfigured
            return
        }
        do {
            let token = try await accessToken(config)
            let request = DriveAPI.initiateRequest(fileName: job.fileName, mimeType: job.mimeType, size: job.totalBytes,
                                                   folderID: job.folderID, takenAt: job.takenAt, accessToken: token.value)
            let (data, response) = try await api.data(for: request)
            guard index(id) != nil, !needsConfig else { inFlight.remove(id); return }
            let http = response as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            if code == 200, let http, let sessionURL = DriveAPI.sessionURL(from: http) {
                let keepBackoff = restartedAfter401.contains(id)
                update(id) {
                    $0.sessionURL = sessionURL
                    $0.sessionStartedAt = .now
                    $0.sentBytes = 0
                    if !keepBackoff { $0.backoff.reset() }
                    $0.message = nil
                }
                clearTransientStatus()
                inFlight.remove(id)
                schedule(id, .chunk(offset: 0))
                return
            }
            switch DriveAPI.outcome(status: code, headers: http?.allHeaderFields ?? [:], body: data) {
            case .unauthorized where !retriedAfter401:
                self.token = nil
                await initiate(id, retriedAfter401: true)
            case .unauthorized, .retryLater, .completed:
                retryLater(id, message: DriveError.http(code).message)
            case .quotaExceeded:
                status = .quotaExceeded
                retryLater(id, message: DriveError.quotaExceeded.message)
            case .failed(let message):
                fail(id, message)
            case .sessionExpired, .resumeAt:
                fail(id, DriveError.http(code).message)
            }
        } catch {
            guard index(id) != nil else { inFlight.remove(id); return }
            switch DriveAPI.classify(error) {
            case .invalidGrant:
                stopEverything()
            case .unreachable:
                status = .unreachable
                retryLater(id, message: DriveError.unreachable.message)
            case .quotaExceeded:
                status = .quotaExceeded
                retryLater(id, message: DriveError.quotaExceeded.message)
            case .http(let code) where code == 0 || code == 408 || code == 429 || code >= 500:
                retryLater(id, message: DriveError.http(code).message)
            case let other:
                fail(id, other.message)
            }
        }
    }

    /// No session yet: wait (backoff, at most 10 minutes) in the app, then try again.
    private func retryLater(_ id: String, message: String) {
        guard let index = index(id) else { inFlight.remove(id); return }
        let delay = jobs[index].backoff.delay
        jobs[index].backoff.fail()
        jobs[index].state = .waiting
        jobs[index].message = message
        persist()
        guard inForeground else {
            // In the background: no retry until the app comes back (resume() → pump()).
            inFlight.remove(id)
            return
        }
        inFlight.insert(id)
        retryTimers[id]?.cancel()
        retryTimers[id] = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            retryTimers[id] = nil
            inFlight.remove(id)
            pump()
        }
    }

    private func fail(_ id: String, _ message: String) {
        inFlight.remove(id)
        update(id) { $0.state = .failed; $0.message = message }
        pump()
    }

    private func clearTransientStatus() {
        if status == .unreachable || status == .quotaExceeded || status == .notConfigured { status = nil }
    }

    /// invalid_grant: the refresh token no longer works. No more requests until a new configuration is saved.
    private func stopEverything() {
        needsConfig = true
        token = nil
        status = .invalidGrant
        cancelEverything()
        for index in jobs.indices where jobs[index].state == .waiting || jobs[index].state == .uploading {
            jobs[index].state = .waiting
            jobs[index].message = DriveError.invalidGrant.message
        }
        persist()
    }

    private func cancelEverything() {
        for timer in retryTimers.values { timer.cancel() }
        retryTimers.removeAll()
        inFlight.removeAll()
        currentTask.removeAll()
        let session = connect()
        Task { for task in await session.allTasks { task.cancel() } }
    }

    // MARK: Background session (chunk PUTs and status PUTs, uploaded from files)

    private enum Request: Equatable {
        case chunk(offset: Int64)
        case status
    }

    @discardableResult private func connect() -> URLSession {
        if let backgroundSession { return backgroundSession }
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 7 * 24 * 3600
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "PortSight.drive.delegate"
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
        backgroundSession = session
        return session
    }

    /// Matches the background session's tasks (which outlive the app) to the queue. A job marked as uploading
    /// with no live task gets a status PUT from pump(); tasks of jobs that are gone are cancelled.
    private func reconcile() {
        guard !reconciling else { return }
        reconciling = true
        let session = connect()
        Task {
            let tasks = await session.allTasks
            let known = Set(jobs.filter { $0.state == .waiting || $0.state == .uploading }.map(\.id))
            for task in tasks where task.state == .running || task.state == .suspended {
                guard let id = task.taskDescription, known.contains(id),
                      currentTask[id] == nil || currentTask[id] == task.taskIdentifier else {
                    task.cancel()
                    continue
                }
                currentTask[id] = task.taskIdentifier
                inFlight.insert(id)
            }
            reconciling = false
            reconciled = true
            pump()
        }
    }

    private func schedule(_ id: String, _ request: Request, after delay: TimeInterval = 0) {
        guard !needsConfig, let job = jobs.first(where: { $0.id == id }), let sessionURL = job.sessionURL else {
            inFlight.remove(id)
            return
        }
        let urlRequest: URLRequest
        let file: URL
        var expected: Int64 = 0
        do {
            switch request {
            case .status:
                urlRequest = DriveAPI.statusRequest(sessionURL: sessionURL, total: job.totalBytes)
                file = try DriveFiles.emptyFile()
            case .chunk(let offset):
                let length = min(DriveAPI.chunkSize, job.totalBytes - offset)
                guard length > 0 else { schedule(id, .status, after: delay); return }
                urlRequest = DriveAPI.chunkRequest(sessionURL: sessionURL, offset: offset, length: length, total: job.totalBytes)
                expected = length
                if offset == 0 && length == job.totalBytes {
                    file = DriveFiles.staged(id)
                } else {
                    file = try DriveFiles.writeChunk(of: id, offset: offset, length: length)
                }
            }
        } catch {
            fail(id, "读取暂存文件失败，请重试")
            return
        }
        let task = connect().uploadTask(with: urlRequest, fromFile: file)
        task.taskDescription = id
        currentTask[id] = task.taskIdentifier
        task.countOfBytesClientExpectsToSend = expected + 2048
        task.countOfBytesClientExpectsToReceive = 4096
        if delay > 0 { task.earliestBeginDate = Date.now.addingTimeInterval(delay) }
        inFlight.insert(id)
        if delay == 0 { update(id) { $0.state = .uploading } }
        task.resume()
    }

    /// A background task finished (delivered on the main queue, in order).
    fileprivate func handle(_ result: DriveTaskResult) {
        guard queueLoaded, let id = result.jobID else { return }
        if let owner = currentTask[id], owner != result.taskIdentifier { return }
        currentTask[id] = nil
        inFlight.remove(id)
        DriveFiles.removeChunk(of: id)
        guard let job = jobs.first(where: { $0.id == id }), job.state == .waiting || job.state == .uploading else { return }
        if needsConfig { return }

        if result.cancelled {
            // Not cancelled by us (we drop the job or stop first): e.g. the app was force-quit. Ask again.
            pump()
            return
        }
        if let transport = result.transport {
            switch transport {
            case .unreachable:
                status = .unreachable
                waitThenAsk(id, message: DriveError.unreachable.message)
            case let other:
                fail(id, other.message)
            }
            return
        }

        switch DriveAPI.outcome(status: result.status, headers: result.headers, body: result.body) {
        case .completed:
            restartedAfter401.remove(id)
            update(id) {
                $0.state = .sent
                $0.sentBytes = $0.totalBytes
                $0.finishedAt = .now
                $0.message = "已发送"
                $0.sessionURL = nil
                $0.backoff.reset()
            }
            clearTransientStatus()
            DriveFiles.removeTemporaryFiles(of: id)
            pump()
        case .resumeAt(let offset):
            restartedAfter401.remove(id)
            update(id) { $0.sentBytes = min(offset, $0.totalBytes); $0.backoff.reset(); $0.message = nil }
            clearTransientStatus()
            schedule(id, offset < job.totalBytes ? .chunk(offset: offset) : .status)
        case .sessionExpired:
            update(id) { $0.sessionURL = nil; $0.sessionStartedAt = nil; $0.sentBytes = 0 }
            step(id)
        case .unauthorized:
            // 401: get a new access token and try again. Session PUTs carry no token (it stays in memory, never in
            // the background session's stored requests), so trying again means a new session with a fresh token.
            // The backoff is kept until a chunk gets through, so a repeating 401 is tried at most every 10 minutes.
            token = nil
            restartedAfter401.insert(id)
            update(id) { $0.sessionURL = nil; $0.sessionStartedAt = nil; $0.sentBytes = 0 }
            retryLater(id, message: DriveError.http(401).message)
        case .quotaExceeded:
            status = .quotaExceeded
            waitThenAsk(id, message: DriveError.quotaExceeded.message)
        case .retryLater:
            waitThenAsk(id, message: DriveError.http(result.status).message)
        case .failed(let message):
            fail(id, message)
        }
    }

    /// Backoff (at most 10 minutes), then a status PUT to learn the offset. Scheduled in the background session
    /// with earliestBeginDate, so it also runs while the app is suspended.
    private func waitThenAsk(_ id: String, message: String) {
        guard let index = index(id) else { return }
        let delay = jobs[index].backoff.delay
        jobs[index].backoff.fail()
        jobs[index].state = .waiting
        jobs[index].message = message
        persist()
        guard inForeground else {
            // In the background: no retry until the app comes back; then a status PUT continues from Drive's offset.
            inFlight.remove(id)
            return
        }
        schedule(id, .status, after: delay)
    }

    /// The app went to the background: uploads already running carry on, but no failed job is retried until the
    /// app comes back. Drops the in-app retry timers and the delayed status PUTs (earliestBeginDate) still waiting
    /// in the background session.
    func pauseRetries() {
        for (id, timer) in retryTimers {
            timer.cancel()
            inFlight.remove(id)
        }
        retryTimers.removeAll()
        let session = connect()
        Task {
            let now = Date.now
            for task in await session.allTasks {
                guard let id = task.taskDescription, let begin = task.earliestBeginDate, begin > now,
                      currentTask[id] == task.taskIdentifier else { continue }
                currentTask[id] = nil
                inFlight.remove(id)
                task.cancel()
            }
        }
    }

    private var inForeground: Bool { UIApplication.shared.applicationState != .background }

    fileprivate func finishBackgroundEvents() {
        persist()
        let handler = backgroundCompletionHandler
        backgroundCompletionHandler = nil
        handler?()
    }
}

// MARK: - Background time

/// Keeps the app running for a short while (about 30 s) after iOS would otherwise suspend it, so a token exchange,
/// session start or staging copy begun during a background wake is not frozen half way.
@MainActor private final class BackgroundTime {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(_ name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in self?.end() }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

// MARK: - Background session delegate

/// What a finished background task reports; secrets and the session URL are not part of it.
nonisolated struct DriveTaskResult: Sendable {
    let jobID: String?
    let taskIdentifier: Int
    let status: Int
    let headers: [String: String]
    let body: Data?
    let cancelled: Bool
    let transport: DriveError?
}

/// Runs on the session's serial delegate queue (off the main actor); every result hops to the main queue in order.
nonisolated final class DriveSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// Response bodies by task; touched only on the serial delegate queue.
    private var bodies: [Int: Data] = [:]

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        bodies[dataTask.taskIdentifier, default: Data()].append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let body = bodies.removeValue(forKey: task.taskIdentifier)
        let http = task.response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (key, value) in http?.allHeaderFields ?? [:] {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        let cancelled = (error as? URLError)?.code == .cancelled
        let result = DriveTaskResult(jobID: task.taskDescription,
                                     taskIdentifier: task.taskIdentifier,
                                     status: http?.statusCode ?? 0,
                                     headers: headers,
                                     body: body,
                                     cancelled: cancelled,
                                     transport: error.map(DriveAPI.classify))
        DispatchQueue.main.async {
            MainActor.assumeIsolated { DriveUploader.shared.handle(result) }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { DriveUploader.shared.finishBackgroundEvents() }
        }
    }
}

// MARK: - Temporary files (only our own copies; never the photo library)

nonisolated enum DriveFiles {
    static var root: URL { DriveUploadStore.defaultURL.deletingLastPathComponent() }
    static func staged(_ id: String) -> URL { root.appendingPathComponent("staged", isDirectory: true).appendingPathComponent(id) }
    static func chunk(_ id: String) -> URL { root.appendingPathComponent("chunks", isDirectory: true).appendingPathComponent(id) }

    private static func prepareDirectory(for file: URL) throws {
        var directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
    }

    /// No data arrived for `idleTimeout` seconds; the request was cancelled.
    struct Stalled: Error {}

    /// Copies the original resource (downloading it from iCloud if needed); returns its size. A copy that gets no
    /// data for `idleTimeout` seconds is cancelled (throws Stalled). On any failure the partial copy is removed, so a
    /// half-copied file is never uploaded.
    static func writeResource(_ resource: PHAssetResource, to file: URL, idleTimeout: TimeInterval = 180) async throws -> Int64 {
        try prepareDirectory(for: file)
        try? FileManager.default.removeItem(at: file)
        do {
            guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
            let writer = try StagingWriter(file: file)
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            options.progressHandler = { _ in writer.touch() }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let request = PHAssetResourceManager.default().requestData(for: resource, options: options,
                                                                          dataReceivedHandler: { data in writer.write(data) },
                                                                          completionHandler: { error in
                    if let failure = writer.finish(error) { continuation.resume(throwing: failure) } else { continuation.resume() }
                })
                writer.watch(request, idleTimeout: idleTimeout)
            }
            let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0 else { throw CocoaError(.fileReadCorruptFile) }
            return size
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }

    /// Bytes offset..<offset+length of the staged file, as a file a background upload task can send.
    static func writeChunk(of id: String, offset: Int64, length: Int64) throws -> URL {
        let handle = try FileHandle(forReadingFrom: staged(id))
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: Int(length)) ?? Data()
        guard Int64(data.count) == length else { throw CocoaError(.fileReadCorruptFile) }
        let file = chunk(id)
        try prepareDirectory(for: file)
        try data.write(to: file, options: .atomic)
        return file
    }

    /// The empty body of a status PUT (background sessions upload only from files).
    static func emptyFile() throws -> URL {
        let file = root.appendingPathComponent("empty")
        if !FileManager.default.fileExists(atPath: file.path) {
            try prepareDirectory(for: file)
            try Data().write(to: file, options: .atomic)
        }
        return file
    }

    static func removeChunk(of id: String) {
        try? FileManager.default.removeItem(at: chunk(id))
    }

    static func removeTemporaryFiles(of id: String) {
        try? FileManager.default.removeItem(at: staged(id))
        removeChunk(of: id)
    }
}

/// Writes the data of one PHAssetResourceManager request to the staged file and cancels the request when no data
/// (or iCloud progress) arrives for a while. Photos calls the handlers on its own queues; everything is locked.
nonisolated private final class StagingWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let handle: FileHandle
    private var lastActivity = Date.now
    private var writeError: Error?
    private var stalled = false
    private var finished = false

    init(file: URL) throws {
        handle = try FileHandle(forWritingTo: file)
    }

    func touch() {
        lock.withLock { lastActivity = .now }
    }

    func write(_ data: Data) {
        lock.withLock {
            lastActivity = .now
            guard writeError == nil, !finished else { return }
            do { try handle.write(contentsOf: data) } catch { writeError = error }
        }
    }

    /// Closes the file; returns the error to report (nil when the copy is complete).
    func finish(_ error: Error?) -> Error? {
        lock.withLock {
            finished = true
            try? handle.close()
            if stalled { return DriveFiles.Stalled() }
            return error ?? writeError
        }
    }

    func watch(_ request: PHAssetResourceDataRequestID, idleTimeout: TimeInterval) {
        Task.detached { [self] in
            while true {
                try? await Task.sleep(for: .seconds(15))
                let cancel: Bool? = lock.withLock {
                    if finished { return nil }
                    if writeError != nil || Date.now.timeIntervalSince(lastActivity) > idleTimeout {
                        stalled = writeError == nil
                        return true
                    }
                    return false
                }
                guard let cancel else { return }
                if cancel {
                    PHAssetResourceManager.default().cancelDataRequest(request)
                    return
                }
            }
        }
    }
}
