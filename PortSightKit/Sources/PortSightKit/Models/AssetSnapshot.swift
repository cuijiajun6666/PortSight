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
public final class AssetSnapshotRecord {
    @Attribute(.unique) public var tradingDate: String
    public var recordedAt: String
    public var totalAssets: Double
    public var principal: Double

    public init(
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

public struct AssetSnapshotDTO: Codable, Identifiable {
    public var id: String { tradingDate }
    public let tradingDate: String
    public let recordedAt: String
    public let totalAssets: Double
    public let principal: Double
    public enum CodingKeys: String, CodingKey {
        case tradingDate = "trading_date"
        case recordedAt = "recorded_at"
        case totalAssets = "total_assets"
        case principal
    }

    public init(tradingDate: String, recordedAt: String, totalAssets: Double, principal: Double) {
        self.tradingDate = tradingDate
        self.recordedAt = recordedAt
        self.totalAssets = totalAssets
        self.principal = principal
    }
}

public struct AssetSnapshotsResponse: Codable {
    public let ok: Bool
    public let snapshots: [AssetSnapshotDTO]

    public init(ok: Bool, snapshots: [AssetSnapshotDTO]) {
        self.ok = ok
        self.snapshots = snapshots
    }
}

extension AssetSnapshotRecord {
    public var dto: AssetSnapshotDTO {
        AssetSnapshotDTO(
            tradingDate: tradingDate,
            recordedAt: recordedAt,
            totalAssets: totalAssets,
            principal: principal
        )
    }
}


