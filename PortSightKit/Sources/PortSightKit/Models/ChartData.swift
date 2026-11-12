//
//  ChartData.swift
//  PortSight
//
//  Data behind the asset trend and allocation charts (the chart views stay in each app).
//

import Foundation

public let testAssetSnapshots: [AssetChartSnapshot] = {
    var result: [AssetChartSnapshot] = []
    var value = 100_000.0

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!

    let startDate = calendar.date(from: DateComponents(
        year: 2026,
        month: 3,
        day: 1,
        hour: 12
    ))!

    for i in 0..<40 {
        value += Double.random(in: -1200...1600)

        let date = calendar.date(
            byAdding: .day,
            value: i,
            to: startDate
        )!

        result.append(
            AssetChartSnapshot(
                date: date,
                value: value
            )
        )
    }

    return result
}()


public struct AssetChartSnapshot: Identifiable {
    public let id = UUID()
    public let date: Date
    public let value: Double
    public let isRecorded: Bool

    public init(date: Date, value: Double, isRecorded: Bool = true) {
        self.date = date
        self.value = value
        self.isRecorded = isRecorded
    }
}



public enum PortfolioTrendMetric: String, CaseIterable, Identifiable {
    case amount = "金额"
    case returnRate = "收益率"

    public var id: String { rawValue }
    public var axisTitle: String { self == .amount ? "Asset" : "Return (%)" }

    // Cumulative return for the current fixed-principal demo, in percentage points.
    // Live accounts with external cash flows must supply cash-flow-adjusted returns.
    public func value(for assets: Double, principal: Double) -> Double {
        switch self {
        case .amount:
            return assets
        case .returnRate:
            guard principal > 0 else { return 0 }
            return (assets - principal) / principal * 100
        }
    }

    public func plotDomain(for values: [Double]) -> ClosedRange<Double> {
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 1
        if self == .returnRate {
            // A zero reference and rounded percentage bounds make return charts readable.
            let lower = min(minimum, 0)
            let upper = max(maximum, 0)
            let span = max(upper - lower, 0.1)
            let step = pow(10, floor(log10(span))) / 2
            return (floor(lower / step) * step - step)...(ceil(upper / step) * step + step)
        }
        let span = max(maximum - minimum, 1)
        return (minimum - span * 0.13)...(maximum + span * 0.15)
    }

    public func annotation(for value: Double) -> String {
        self == .amount ? String(format: "$%.0f", value) : String(format: "%+.2f%%", value)
    }
}

// Interpolate screen-space heights; x coordinates and the plot bounds stay fixed.
// This avoids mixing dollar and percentage values during a transition.
public enum VerticalTrendMorph {
    public static func resample(_ values: [Double], count: Int) -> [Double] {
        guard count > 0, !values.isEmpty else { return [] }
        guard count > 1, values.count > 1 else {
            return Array(repeating: values[0], count: count)
        }
        return (0..<count).map { index in
            let position = Double(index) / Double(count - 1) * Double(values.count - 1)
            let lower = Int(floor(position))
            let upper = min(lower + 1, values.count - 1)
            return values[lower] + (values[upper] - values[lower]) * (position - Double(lower))
        }
    }

    public static func values(from start: [Double], to target: [Double], progress: Double) -> [Double] {
        guard start.count == target.count else { return target }
        let t = min(max(progress, 0), 1)
        let eased = t * t * t * (t * (t * 6 - 15) + 10)
        return zip(start, target).map { from, to in from + (to - from) * eased }
    }
}

public enum AssetTrendRange: String, CaseIterable, Identifiable {
    case week = "1W"
    case month = "1M"
    case all = "All"

    public var id: String { rawValue }

    public var dayCount: Int? {
        switch self {
        case .week:
            return 7
        case .month:
            return 30
        case .all:
            return nil
        }
    }
}



public struct AllocationItem: Identifiable {
    public let name: String
    public let value: Double

    public var id: String { name }

    public init(name: String, value: Double) {
        self.name = name
        self.value = value
    }
}
