//
//  MarketStatusResponse.swift
//  PortSight
//
//  Created by Chris Cui on 5/5/2026.
//

import Combine
import Foundation

public enum MarketSession {
    case unknown
    case regular
    case pre
    case after
    case overnight
    case closed
}

public struct MarketStatusResponse: Codable {
    public let ok: Bool
    public let session: String?
    public let display_status: String?
    public let is_market_open: Bool?
    public let is_regular_open: Bool?
    public let is_extended_open: Bool?
    public let is_trading_day: Bool?
    public let now_new_york: String?
    public let market_us_raw: String?
    public let market_us: String?
    public let qot_logined: Bool?
    public let trd_logined: Bool?
    public let program_status_type: String?
    public let error: String?

    public init(ok: Bool, session: String?, display_status: String?, is_market_open: Bool?, is_regular_open: Bool?, is_extended_open: Bool?, is_trading_day: Bool?, now_new_york: String?, market_us_raw: String?, market_us: String?, qot_logined: Bool?, trd_logined: Bool?, program_status_type: String?, error: String?) {
        self.ok = ok
        self.session = session
        self.display_status = display_status
        self.is_market_open = is_market_open
        self.is_regular_open = is_regular_open
        self.is_extended_open = is_extended_open
        self.is_trading_day = is_trading_day
        self.now_new_york = now_new_york
        self.market_us_raw = market_us_raw
        self.market_us = market_us
        self.qot_logined = qot_logined
        self.trd_logined = trd_logined
        self.program_status_type = program_status_type
        self.error = error
    }
}

@MainActor
public final class MarketStatusViewModel: ObservableObject {
    @Published public var marketUS: String?
    @Published public var session: MarketSession = .unknown
    @Published public var displayStatus = "获取中"
    @Published public var errorMessage: String?
    private var task: Task<Void, Never>?

    public var isUSRegularTrading: Bool {
        session == .regular
    }

    public var refreshInterval: Double {
        switch session {
        case .regular:
            return 3
        case .pre, .after, .overnight:
            return 15
        case .closed, .unknown:
            return 60
        }
    }

    public func fetchMarketStatus() async {
        // No market-status server any more: the session follows the New York clock (polled like the server was).
        if DemoPortfolioData.enabled { applyClock(); return }
        guard let url = BackendConfig.url(path: "market_status") else { return }

        do {
            var request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                timeoutInterval: 10
            )
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")

            let (data, _) = try await URLSession.shared.data(for: request)
            let result = try await CacheManager.decode(MarketStatusResponse.self, from: data)

            if result.ok {
                let newMarketUS = result.market_us_raw ?? result.market_us
                if marketUS != newMarketUS {
                    marketUS = newMarketUS
                }
                update(from: result)
                if errorMessage != nil {
                    errorMessage = nil
                }
            } else {
                setErrorStatus(result.error)
            }
        } catch {
            setErrorStatus(error.localizedDescription)
        }
    }

    public func update(from response: MarketStatusResponse) {
        var nextSession: MarketSession
        if let normalizedSession = response.session {
            nextSession = mapSession(normalizedSession)
        } else {
            nextSession = mapLegacySession(response.market_us_raw ?? response.market_us)
        }

        let inferredOvernight = shouldTreatClosedAfterHoursEndAsOvernight(response)
        if nextSession == .closed, inferredOvernight {
            nextSession = .overnight
        }

        let nextDisplayStatus: String
        if inferredOvernight, response.display_status == "休市" {
            nextDisplayStatus = label(for: nextSession)
        } else {
            nextDisplayStatus = response.display_status ?? label(for: nextSession)
        }
        applyStatus(session: nextSession, displayStatus: nextDisplayStatus)
    }

    private func applyStatus(session newSession: MarketSession, displayStatus newDisplayStatus: String) {
        if session != newSession {
            session = newSession
        }
        if displayStatus != newDisplayStatus {
            displayStatus = newDisplayStatus
        }
    }

    private func setErrorStatus(_ message: String?) {
        if errorMessage != message {
            errorMessage = message
        }
        applyStatus(session: .closed, displayStatus: "获取失败")
    }

    private func mapSession(_ value: String) -> MarketSession {
        switch value.lowercased() {
        case "regular", "open", "regular_open":
            return .regular
        case "pre", "premarket", "pre_market":
            return .pre
        case "after", "after_hours", "postmarket", "post_market":
            return .after
        case "overnight", "night", "night_trading":
            return .overnight
        case "closed":
            return .closed
        case "unknown":
            return .unknown
        default:
            return .closed
        }
    }

    private func mapLegacySession(_ apiValue: String?) -> MarketSession {
        switch apiValue {
        case "MORNING", "AFTERNOON":
            return .regular
        case "PRE_MARKET_BEGIN", "PRE_MARKET":
            return .pre
        case "AFTER_HOURS_BEGIN", "AFTER_HOURS":
            return .after
        case "OVERNIGHT", "US_OVERNIGHT", "NIGHT_OPEN", "NIGHT_TRADING":
            return .overnight
        default:
            return .closed
        }
    }

    private func shouldTreatClosedAfterHoursEndAsOvernight(_ response: MarketStatusResponse) -> Bool {
        guard (response.session?.lowercased() == "closed" || response.session == nil),
              (response.market_us_raw ?? response.market_us) == "AFTER_HOURS_END",
              let nowNewYork = response.now_new_york,
              let date = Self.newYorkStatusDate(from: nowNewYork),
              let newYorkTimeZone = TimeZone(identifier: "America/New_York") else {
            return false
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYorkTimeZone

        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)

        if hour >= 20 {
            return (2...5).contains(weekday) || weekday == 1
        }

        if hour < 4 {
            return (2...6).contains(weekday)
        }

        return false
    }

    private static func newYorkStatusDate(from value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func label(for session: MarketSession) -> String {
        switch session {
        case .unknown:
            return "获取中"
        case .regular:
            return "盘中"
        case .pre:
            return "盘前"
        case .after:
            return "盘后"
        case .overnight:
            return "夜盘"
        case .closed:
            return "休市"
        }
    }
    
    public func startPolling(every seconds: Double = 20) {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.fetchMarketStatus()
                try? await Task.sleep(
                    nanoseconds: UInt64(seconds * 1_000_000_000)
                )
            }
        }
    }
    public func stopPolling() {
        task?.cancel()
        task = nil
    }
    deinit {
        task?.cancel()
    }

    public init() {}
}
