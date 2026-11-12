//
//  TerminalLineSeal.swift
//  PortSight
//
//  Crypto forward seal for trading lines, the same rule as the Mac app's DesktopLineSeal: a shadow ledger
//  shows status, counts and checks only from 2026-10-22, and its returns open again on 2027-05-06 (UTC).
//  Paper and live accounts are never sealed.
//

import Foundation
import PortSightKit

enum TerminalLineSeal {
    static let start = BacktestRun.sealStart
    static let opens = Date(timeIntervalSince1970: 1_809_561_600) // 2027-05-06 00:00 UTC
    static let opensTitle = "2027-05-06"
    /// One-line note shown in place of a sealed line's returns.
    static let note = "影子账本在前向封存期，收益 \(opensTitle) 开放"

    static func isSealed(_ line: TradingLine, now: Date = .now) -> Bool {
        line.mode == .shadow && now >= start && now < opens
    }
}
