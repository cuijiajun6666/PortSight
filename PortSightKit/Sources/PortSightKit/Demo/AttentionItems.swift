//
//  AttentionItems.swift
//  PortSight
//
//  The 总览 "需要处理" rules, shared by both apps: critical notices not yet acknowledged, unread critical
//  relay alerts, volumes that are not mounted, and mounted volumes at 80% or more.
//

import Foundation

public struct AttentionItem: Identifiable {
    public enum Target { case notice(DemoNotice), alert(TerminalAlert), server }
    /// critical draws red, warning orange.
    public enum Tone { case critical, warning }

    public let id: String
    public let icon: String
    public let tone: Tone
    public let title: String
    public let detail: String
    public let target: Target

    public init(id: String, icon: String, tone: Tone, title: String, detail: String, target: Target) {
        self.id = id
        self.icon = icon
        self.tone = tone
        self.title = title
        self.detail = detail
        self.target = target
    }
}

public enum AttentionItems {
    /// Volume names in display order: the same titles the 总览 / 服务器 volume rows show (StorageVolume.layout).
    public static var diskNames: [(key: String, name: String)] {
        StorageVolume.layout.map { (key: $0.key, name: $0.title) }
    }
    /// Used share (percent) at which a mounted volume is listed, and at which it turns red.
    public static let diskWarning: Double = 80
    public static let diskCritical: Double = 90

    public static func build(demo: PortfolioDemo, terminal: TerminalDemo, host: HostStatus?, now: Date = .now) -> [AttentionItem] {
        build(notices: demo.pendingCritical, alerts: terminal.alerts, read: terminal.read, host: host, now: now)
    }

    /// - Parameter notices: notices still waiting for acknowledgement (PortfolioDemo.pendingCritical): critical ones
    ///   draw red, the rest orange.
    public static func build(notices: [DemoNotice], alerts: [TerminalAlert], read: Set<String>,
                             host: HostStatus?, now: Date = .now) -> [AttentionItem] {
        var items: [AttentionItem] = notices.map {
            AttentionItem(id: "n-" + $0.id,
                          icon: $0.severity == "critical" ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill",
                          tone: $0.severity == "critical" ? .critical : .warning,
                          title: $0.title, detail: $0.time, target: .notice($0))
        }
        // One row per kind of alert (the id before "@"): a job whose heartbeat keeps failing is listed once, newest.
        var kinds = Set<String>()
        let unread = alerts.filter { $0.severity == .critical && !read.contains($0.id) }
            .sorted { $0.at > $1.at }
            .filter { kinds.insert(PushEventRef.kind(of: $0.id)).inserted }
        items += unread.map {
            AttentionItem(id: "a-" + $0.id, icon: "exclamationmark.triangle.fill", tone: .critical, title: $0.title,
                          detail: $0.source + " · " + TerminalFormat.relative($0.at, now: now), target: .alert($0))
        }

        let names = Dictionary(uniqueKeysWithValues: diskNames.map { ($0.key, $0.name) })
        let order = diskNames.map(\.key)
        let disks = host?.disks ?? [:]
        let keys = order.filter { disks[$0] != nil }
            + disks.keys.filter { !order.contains($0) && $0 != "local_fallback" }.sorted()

        let unmounted = keys.filter { (disks[$0] ?? nil)?.mounted == false }.map { names[$0] ?? $0 }
        if !unmounted.isEmpty {
            items.append(AttentionItem(id: "d-unmounted", icon: "externaldrive.badge.xmark", tone: .warning,
                                       title: unmounted.joined(separator: "、") + "没有挂载",
                                       detail: "备份和照片会暂存在内置盘", target: .server))
        }
        for key in keys {
            guard let disk = disks[key] ?? nil, disk.mounted != false,
                  let used = disk.used_pct, used >= diskWarning else { continue }
            let free = disk.free_gb.map { String(format: "%.0f", $0) } ?? "—"
            items.append(AttentionItem(id: "d-" + key, icon: "externaldrive.badge.exclamationmark",
                                       tone: used >= diskCritical ? .critical : .warning,
                                       title: (names[key] ?? key) + "已用 \(Int(used))%",
                                       detail: "剩 \(free) GB", target: .server))
        }
        return items
    }
}
