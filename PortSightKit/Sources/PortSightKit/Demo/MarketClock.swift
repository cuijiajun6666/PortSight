//
//  MarketClock.swift
//  PortSightKit
//
//  The US stock market's session from the New York clock: 盘前 4:00–9:30, 盘中 9:30–16:00 (13:00 on early-close
//  days), 盘后 until 20:00, 夜盘 20:00–4:00 on trading nights, 休市 on weekends and NYSE holidays. It replaces the
//  fixed 「休市」 the built-in portfolio showed; no server is asked (the relay has no market-status endpoint).
//

import Foundation

public nonisolated enum MarketClock {
    public static let newYork = TimeZone(identifier: "America/New_York")!

    /// NYSE full-day closures (New York dates).
    static let holidays: Set<String> = [
        "2026-01-01", "2026-01-19", "2026-02-16", "2026-04-03", "2026-05-25", "2026-06-19", "2026-07-03",
        "2026-09-07", "2026-11-26", "2026-12-25",
        "2027-01-01", "2027-01-18", "2027-02-15", "2027-03-26", "2027-05-31", "2027-06-18", "2027-07-05",
        "2027-09-06", "2027-11-25", "2027-12-24",
    ]

    /// Regular session ends at 13:00.
    static let earlyCloses: Set<String> = ["2026-11-27", "2026-12-24", "2027-11-26"]

    public static func isTradingDay(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        let weekday = calendar.component(.weekday, from: date)
        return weekday != 1 && weekday != 7 && !holidays.contains(day(date))
    }

    /// The session at `date`, and its Chinese name.
    public static func session(at date: Date = .now) -> (session: MarketSession, title: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let today = isTradingDay(date)
        let close = earlyCloses.contains(day(date)) ? 13 * 60 : 16 * 60
        if today {
            if minute >= 4 * 60, minute < 9 * 60 + 30 { return (.pre, "盘前") }
            if minute >= 9 * 60 + 30, minute < close { return (.regular, "盘中") }
            if minute >= close, minute < 20 * 60 { return (.after, "盘后") }
        }
        // 夜盘: from 20:00 on a trading day that is followed by one, until 4:00 of that next day.
        if minute >= 20 * 60, today, let next = calendar.date(byAdding: .day, value: 1, to: date), isTradingDay(next) {
            return (.overnight, "夜盘")
        }
        if minute < 4 * 60, today, let previous = calendar.date(byAdding: .day, value: -1, to: date), isTradingDay(previous) {
            return (.overnight, "夜盘")
        }
        return (.closed, "休市")
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = newYork
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

extension MarketStatusViewModel {
    /// The session from the New York clock (MarketClock).
    public func applyClock(now: Date = .now) {
        let current = MarketClock.session(at: now)
        if session != current.session { session = current.session }
        if displayStatus != current.title { displayStatus = current.title }
    }
}
