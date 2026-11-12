//
//  NotificationFeed.swift
//  PortSight
//
//  One list for the bell: the original account notices (DemoNotice) together with the relay alerts
//  (TerminalAlert). Read state stays where it already lives: PortfolioDemo.read and TerminalDemo.read.
//

import Foundation

public struct FeedItem: Identifiable, Hashable {
    public enum Source: Hashable { case notice(String), alert(String) }

    public let source: Source
    public let title: String
    public let detail: String
    /// critical / warning / info, the same values DemoNotice.severity uses.
    public let severity: String
    public let category: String
    public let time: String
    /// Sort key: notices carry only a display time, so they sort by their fixed list order ahead of older alerts.
    public let order: Double

    public var id: String {
        switch source {
        case .notice(let id): "notice:" + id
        case .alert(let id): "alert:" + id
        }
    }
}

public enum NotificationFeed {
    /// Category titles offered by the bell's category filter, in a stable order.
    public static let categories: [String] = {
        var seen: [String] = []
        for title in DemoPortfolioData.notices.map(\.category) + AlertCategory.allCases.map(\.title) where !seen.contains(title) {
            seen.append(title)
        }
        return seen
    }()

    public static func items(notices: [DemoNotice], alerts: [TerminalAlert], now: Date = .now) -> [FeedItem] {
        // Relay notices carry a time and interleave with the alerts; the built-in ones keep their list order on top.
        let fromNotices = notices.enumerated().map { index, notice in
            FeedItem(source: .notice(notice.id), title: notice.title, detail: notice.detail, severity: notice.severity,
                     category: notice.category, time: notice.time,
                     order: notice.at.map { 1_000 + now.timeIntervalSince($0) / 60 } ?? Double(index))
        }
        let fromAlerts = alerts.map { alert in
            FeedItem(source: .alert(alert.id), title: alert.title, detail: alert.detail, severity: alert.severity.rawValue,
                     category: alert.category.title, time: TerminalFormat.relative(alert.at, now: now),
                     order: 1_000 + now.timeIntervalSince(alert.at) / 60)
        }
        return (fromNotices + fromAlerts).sorted { $0.order < $1.order }
    }
}
