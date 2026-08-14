//
//  AssetSnapshot.swift
//  PortSight
//
//  Created by Chris Cui on 2/5/2026.
//


import Foundation
import Combine
import SwiftData

@Model
final class AssetSnapshotRecord {
    @Attribute(.unique) var tradingDate: String
    var recordedAt: String
    var totalAssets: Double
    var principal: Double

    init(
        tradingDate: String,
        recordedAt: String,
        totalAssets: Double,
        principal: Double
    ) {
        self.tradingDate = tradingDate
        self.recordedAt = recordedAt
        self.totalAssets = totalAssets
        self.principal = principal
    }
}

struct AssetSnapshotDTO: Codable, Identifiable {
    var id: String { tradingDate }
    let tradingDate: String
    let recordedAt: String
    let totalAssets: Double
    let principal: Double
    enum CodingKeys: String, CodingKey {
        case tradingDate = "trading_date"
        case recordedAt = "recorded_at"
        case totalAssets = "total_assets"
        case principal
    }
}

struct AssetSnapshotsResponse: Codable {
    let ok: Bool
    let snapshots: [AssetSnapshotDTO]
}

extension AssetSnapshotRecord {
    var dto: AssetSnapshotDTO {
        AssetSnapshotDTO(
            tradingDate: tradingDate,
            recordedAt: recordedAt,
            totalAssets: totalAssets,
            principal: principal
        )
    }
}


@MainActor
class AssetSnapshotsViewModel: ObservableObject {
    @Published var snapshots: [AssetSnapshotDTO] = []
    @Published var errorMessage: String?

    private let cacheKey = "asset_snapshots_cache"

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return f
    }()

    init() {
        loadCache()
    }

    var chartSnapshots: [AssetChartSnapshot] {
        snapshots.compactMap { s in
            guard let date = formatter.date(from: s.tradingDate) else { return nil }

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/New_York")!

            let noonDate = calendar.date(
                bySettingHour: 12,
                minute: 0,
                second: 0,
                of: date
            ) ?? date

            return AssetChartSnapshot(
                date: noonDate,
                value: s.totalAssets
            )
        }
    }

    func loadCache() {
        if let cached = CacheManager.load([AssetSnapshotDTO].self, key: cacheKey) {
            snapshots = cached
        }
    }

    func fetchSnapshots() async {
        guard let url = BackendConfig.url(path: "asset_snapshots") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try await CacheManager.decode(AssetSnapshotsResponse.self, from: data)

            if result.ok {
                let sortedSnapshots = await sorted(result.snapshots)
                snapshots = sortedSnapshots
                errorMessage = nil
                await CacheManager.saveAsync(sortedSnapshots, key: cacheKey)
            } else {
                errorMessage = "资产快照接口返回失败"
            }
        } catch {
            errorMessage = error.localizedDescription
            print("fetch snapshots error:", error)
        }
    }

    func fetchAndPersistSnapshots(modelContext: ModelContext) async {
        do {
            let sortedSnapshots = try await fetchServerSnapshots()
            try persist(sortedSnapshots, modelContext: modelContext)

            snapshots = sortedSnapshots
            errorMessage = nil
            await CacheManager.saveAsync(sortedSnapshots, key: cacheKey)
        } catch {
            errorMessage = error.localizedDescription
            print("fetch and persist snapshots error:", error)
        }
    }

    func fetchServerSnapshots() async throws -> [AssetSnapshotDTO] {
        guard let url = BackendConfig.url(path: "asset_snapshots") else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let result = try await CacheManager.decode(AssetSnapshotsResponse.self, from: data)

        guard result.ok else {
            throw URLError(.badServerResponse)
        }

        return await sorted(result.snapshots)
    }

    func replacePersistedSnapshots(
        _ serverSnapshots: [AssetSnapshotDTO],
        modelContext: ModelContext
    ) throws {
        try persist(serverSnapshots, modelContext: modelContext)
    }

    private func persist(_ serverSnapshots: [AssetSnapshotDTO], modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<AssetSnapshotRecord>()
        let existingRecords = try modelContext.fetch(descriptor)
        let serverDates = Set(serverSnapshots.map(\.tradingDate))
        var recordsByDate: [String: AssetSnapshotRecord] = [:]
        var didChange = false

        for record in existingRecords {
            if serverDates.contains(record.tradingDate) {
                if recordsByDate[record.tradingDate] == nil {
                    recordsByDate[record.tradingDate] = record
                } else {
                    modelContext.delete(record)
                    didChange = true
                }
            } else {
                modelContext.delete(record)
                didChange = true
            }
        }

        for snapshot in serverSnapshots {
            if let record = recordsByDate[snapshot.tradingDate] {
                if record.recordedAt != snapshot.recordedAt ||
                    record.totalAssets != snapshot.totalAssets ||
                    record.principal != snapshot.principal {
                    record.recordedAt = snapshot.recordedAt
                    record.totalAssets = snapshot.totalAssets
                    record.principal = snapshot.principal
                    didChange = true
                }
            } else {
                let record = AssetSnapshotRecord(
                    tradingDate: snapshot.tradingDate,
                    recordedAt: snapshot.recordedAt,
                    totalAssets: snapshot.totalAssets,
                    principal: snapshot.principal
                )
                modelContext.insert(record)
                recordsByDate[snapshot.tradingDate] = record
                didChange = true
            }
        }

        if didChange {
            try modelContext.save()
        }
    }

    private func sorted(_ snapshots: [AssetSnapshotDTO]) async -> [AssetSnapshotDTO] {
        await Task.detached(priority: .utility) {
            snapshots.sorted { $0.tradingDate < $1.tradingDate }
        }.value
    }
}
