//
//  AlertSeverityStyle.swift
//  PortSight
//
//  One severity mapping for both apps. AlertSeverity already carries its title (严重 / 警告 / 信息) and its SF
//  Symbol; this adds the tint and a way to read the severity string that notices and feed items carry, so the
//  screens stop switching on "critical" / "warning" themselves.
//

import SwiftUI

extension AlertSeverity {
    /// Notices and feed items carry their severity as a string ("critical", "warning", "info").
    /// Anything unknown reads as info.
    public init(noticeSeverity raw: String) {
        self = AlertSeverity(rawValue: raw) ?? .info
    }

    /// The system colour for this severity: red, orange or blue.
    public var tint: Color {
        switch self {
        case .critical: .red
        case .warning: .orange
        case .info: .blue
        }
    }
}
