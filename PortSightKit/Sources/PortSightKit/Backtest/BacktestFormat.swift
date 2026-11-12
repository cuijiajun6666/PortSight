//
//  BacktestFormat.swift
//  PortSightKit
//
//  Text for the 回测 viewers (Mac and iOS): UTC times, signed / plain percents, prices and holding times.
//

import Foundation

public enum BacktestFormat {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    public static func time(_ milliseconds: Double) -> String { formatter.string(from: Date(milliseconds: milliseconds)) + " UTC" }
    nonisolated public static func percent(_ fraction: Double, digits: Int = 2) -> String { String(format: "%+.\(digits)f%%", fraction * 100) }
    nonisolated public static func plainPercent(_ fraction: Double, digits: Int = 1) -> String { String(format: "%.\(digits)f%%", fraction * 100) }

    nonisolated public static func price(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return value >= 1_000 ? String(format: "%.1f", value) : value >= 10 ? String(format: "%.2f", value) : String(format: "%.4f", value)
    }

    /// A reported figure, or "—" when the export left it out.
    public static func percent(_ fraction: Double?, digits: Int = 2) -> String {
        guard let fraction, fraction.isFinite else { return "—" }
        return percent(fraction, digits: digits)
    }

    public static func hours(_ hours: Double) -> String {
        if hours < 1 { return "\(Int((hours * 60).rounded())) 分钟" }
        if hours < 48 { return String(format: "%.1f 小时", hours) }
        return String(format: "%.1f 天", hours / 24)
    }
}
