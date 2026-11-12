//
//  分时图.swift
//  PortSight
//
//  Created by Chris Cui on 17/5/2026.
//

import Charts
import SwiftUI
import Foundation
import Combine

public struct IntradayPricePoint: Codable, Identifiable, Equatable {
    public var id: String { "\(code)-\(time)" }

    public let code: String
    public let name: String?
    public let time: String
    public let isBlank: Bool
    public let openedMins: Int?
    public let curPrice: Double
    public let lastClose: Double?
    public let avgPrice: Double?
    public let volume: Double?
    public let turnover: Double?

    public var date: Date? {
        Self.dateFormatter.date(from: time)
            ?? Self.fractionalDateFormatter.date(from: time)
    }

    public var isRegularTradingMinute: Bool {
        guard let minute = openedMins ?? minuteOfDayFromTimeString else {
            return false
        }

        return (9 * 60 + 30)...(16 * 60) ~= minute
    }

    private var minuteOfDayFromTimeString: Int? {
        let parts = time.split(separator: " ")
        guard parts.count == 2 else { return nil }

        let timeParts = parts[1].split(separator: ":")
        guard timeParts.count >= 2,
              let hour = Int(timeParts[0]),
              let minute = Int(timeParts[1]) else {
            return nil
        }

        return hour * 60 + minute
    }

    public enum CodingKeys: String, CodingKey {
        case code
        case name
        case time
        case isBlank = "is_blank"
        case openedMins = "opened_mins"
        case curPrice = "cur_price"
        case lastClose = "last_close"
        case avgPrice = "avg_price"
        case volume
        case turnover
    }

    public init(
        code: String,
        name: String? = nil,
        time: String,
        isBlank: Bool = false,
        openedMins: Int? = nil,
        curPrice: Double,
        lastClose: Double? = nil,
        avgPrice: Double? = nil,
        volume: Double? = nil,
        turnover: Double? = nil
    ) {
        self.code = code
        self.name = name
        self.time = time
        self.isBlank = isBlank
        self.openedMins = openedMins
        self.curPrice = curPrice
        self.lastClose = lastClose
        self.avgPrice = avgPrice
        self.volume = volume
        self.turnover = turnover
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        code = try container.decodeIfPresent(String.self, forKey: .code) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name)
        time = try container.decode(String.self, forKey: .time)
        isBlank = try container.decodeIfPresent(Bool.self, forKey: .isBlank) ?? false
        openedMins = try container.decodeIfPresent(Int.self, forKey: .openedMins)
        curPrice = try container.decode(Double.self, forKey: .curPrice)
        lastClose = try container.decodeIfPresent(Double.self, forKey: .lastClose)
        avgPrice = try container.decodeIfPresent(Double.self, forKey: .avgPrice)
        volume = try container.decodeIfPresent(Double.self, forKey: .volume)
        turnover = try container.decodeIfPresent(Double.self, forKey: .turnover)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(code, forKey: .code)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(time, forKey: .time)
        try container.encode(isBlank, forKey: .isBlank)
        try container.encodeIfPresent(openedMins, forKey: .openedMins)
        try container.encode(curPrice, forKey: .curPrice)
        try container.encodeIfPresent(lastClose, forKey: .lastClose)
        try container.encodeIfPresent(avgPrice, forKey: .avgPrice)
        try container.encodeIfPresent(volume, forKey: .volume)
        try container.encodeIfPresent(turnover, forKey: .turnover)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let fractionalDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

}

public struct IntradayMarketResponse: Codable {
    public let ok: Bool
    public let source: String?
    public let marketOpen: Bool?
    public let tradingDate: String?
    public let refreshIntervalSeconds: Double?
    public let codes: [String]?
    public let summary: [String: IntradayMarketSummary]?
    public let data: [String: [IntradayPricePoint]]?
    public let error: String?

    public enum CodingKeys: String, CodingKey {
        case ok
        case source
        case marketOpen = "market_open"
        case tradingDate = "trading_date"
        case refreshIntervalSeconds = "refresh_interval_seconds"
        case codes
        case summary
        case data
        case error
    }

    public func points(for symbol: String) -> [IntradayPricePoint] {
        guard let data else { return [] }

        for key in candidateDataKeys(for: symbol) {
            if let points = data[key] {
                return points
            }
        }

        return data.first?.value ?? []
    }

    private func candidateDataKeys(for symbol: String) -> [String] {
        let uppercasedSymbol = symbol.uppercased()
        let shortSymbol = uppercasedSymbol
            .replacingOccurrences(of: "US.", with: "")

        var keys = [
            uppercasedSymbol,
            "US.\(shortSymbol)"
        ]

        switch shortSymbol {
        case "SPX", "SPY":
            keys.append("US.SPY")
        case "IXIC", "QQQ":
            keys.append("US.QQQ")
        case "DJI", "DIA":
            keys.append("US.DIA")
        default:
            break
        }

        return keys.reduce(into: [String]()) { result, key in
            guard !result.contains(key) else { return }
            result.append(key)
        }
    }

    public func summary(for symbol: String) -> IntradayMarketSummary? {
        guard let summary else { return nil }

        for key in candidateDataKeys(for: symbol) {
            if let item = summary[key] {
                return item
            }
        }

        return summary.first?.value
    }

    public init(ok: Bool, source: String?, marketOpen: Bool?, tradingDate: String?, refreshIntervalSeconds: Double?, codes: [String]?, summary: [String: IntradayMarketSummary]?, data: [String: [IntradayPricePoint]]?, error: String?) {
        self.ok = ok
        self.source = source
        self.marketOpen = marketOpen
        self.tradingDate = tradingDate
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.codes = codes
        self.summary = summary
        self.data = data
        self.error = error
    }
}

public struct IntradayMarketSummary: Codable, Equatable {
    public let code: String
    public let chartCode: String?
    public let quoteCode: String?
    public let name: String?
    public let price: Double?
    public let previousClose: Double?
    public let change: Double?
    public let changePercent: Double?
    public let latestTime: String?
    public let points: Int?
    public let quoteError: String?

    public enum CodingKeys: String, CodingKey {
        case code
        case chartCode = "chart_code"
        case quoteCode = "quote_code"
        case name
        case price
        case previousClose = "previous_close"
        case change
        case changePercent = "change_percent"
        case latestTime = "latest_time"
        case points
        case quoteError = "quote_error"
    }

    public init(code: String, chartCode: String?, quoteCode: String?, name: String?, price: Double?, previousClose: Double?, change: Double?, changePercent: Double?, latestTime: String?, points: Int?, quoteError: String?) {
        self.code = code
        self.chartCode = chartCode
        self.quoteCode = quoteCode
        self.name = name
        self.price = price
        self.previousClose = previousClose
        self.change = change
        self.changePercent = changePercent
        self.latestTime = latestTime
        self.points = points
        self.quoteError = quoteError
    }
}

public struct IntradayMarketCache: Codable {
    public let tradingDate: String
    public let source: String?
    public let marketOpen: Bool
    public let refreshIntervalSeconds: Double
    public let points: [IntradayPricePoint]
    public let summary: IntradayMarketSummary?

    public init(tradingDate: String, source: String?, marketOpen: Bool, refreshIntervalSeconds: Double, points: [IntradayPricePoint], summary: IntradayMarketSummary?) {
        self.tradingDate = tradingDate
        self.source = source
        self.marketOpen = marketOpen
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.points = points
        self.summary = summary
    }
}

