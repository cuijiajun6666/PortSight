//
//  ConnectionStatus.swift
//  PortSight
//
//  How this device reaches the Mac mini in Sydney: the relay is on a public HTTPS address (Tailscale Funnel), so
//  devices need no Tailscale; 直连 / 通过中转 / 暂时连不上 describe the route quality. The owner's devices show
//  ServerStore.connection (measured); DemoConnection is the sample before pairing and the family edition's.
//

import Foundation

public struct ConnectionStatus: Equatable {
    public enum Path: String, Equatable {
        case direct, relayed, offline

        public var title: String {
            switch self {
            case .direct: "直连"
            case .relayed: "通过中转"
            case .offline: "暂时连不上"
            }
        }

        public var icon: String {
            switch self {
            case .direct: "bolt.horizontal.circle.fill"
            case .relayed: "arrow.triangle.branch"
            case .offline: "wifi.exclamationmark"
            }
        }

        public var advice: String {
            switch self {
            case .direct: "网络很好，照片和文件都能直接传。"
            case .relayed: "跨境线路经中转节点，看照片没问题，大文件会放到夜间上传。"
            case .offline: "先看已缓存的内容，恢复后会自动补传。"
            }
        }
    }

    public let path: Path
    public let relayName: String?
    public let latencyMs: Int?
    public let lastSync: Date?
    public let queuedUploads: Int
    public let serverName: String
    public let serverPlace: String

    /// The relay's public address goes through Tailscale Funnel.
    public static let funnel = "Tailscale Funnel"

    /// What the route means for the person looking at it.
    public var advice: String {
        if relayName == Self.funnel {
            return path == .offline ? "连不上 Mac mini：检查网络，恢复后自动重连。" : "经 Tailscale Funnel 的公网 HTTPS 地址连接 Mac mini，这台设备不用开 Tailscale。"
        }
        return path.advice
    }

    /// Latency in a few words, for the family edition.
    public var speedTitle: String {
        guard let latencyMs else { return "—" }
        switch latencyMs {
        case ..<120: return "很快"
        case ..<300: return "正常"
        default: return "较慢"
        }
    }
}

public enum DemoConnection {
    /// Family in China: Sydney is reached through the self-hosted Tokyo relay.
    public static let family = ConnectionStatus(path: .relayed, relayName: "东京中转", latencyMs: 186,
                                                lastSync: Date().addingTimeInterval(-12 * 60), queuedUploads: 23,
                                                serverName: "Mac mini", serverPlace: "悉尼")

    /// The owner's phone in Sydney.
    public static let owner = ConnectionStatus(path: .direct, relayName: nil, latencyMs: 9,
                                               lastSync: Date().addingTimeInterval(-60), queuedUploads: 0,
                                               serverName: "Mac mini", serverPlace: "悉尼")

    /// The owner's device while the relay cannot be reached (the 连不上服务器 banner is up).
    public static let ownerOffline = ConnectionStatus(path: .offline, relayName: nil, latencyMs: nil, lastSync: nil,
                                                      queuedUploads: 0, serverName: "Mac mini", serverPlace: "悉尼")
}
