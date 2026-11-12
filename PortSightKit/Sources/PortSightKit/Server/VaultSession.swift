//
//  VaultSession.swift
//  PortSight
//
//  Whether the 文件保险箱 is open right now. After unlocking, leaving the vault (another tab, going back, or
//  the app going to the background) keeps it open for a short grace period; coming back later than that asks
//  for Face ID or the passcode again. The lock button closes it at once. Shared by every place the vault is shown.
//

import Foundation
import Observation

@Observable
public final class VaultSession {
    public static let shared = VaultSession()
    public static let grace: TimeInterval = 5 * 60

    public private(set) var isUnlocked = false
    /// Set by the lock button: the lock screen that follows waits for a tap instead of asking for Face ID
    /// straight away. Cleared once the vault is left.
    public private(set) var lockedByHand = false
    /// True while the Face ID sheet is up (the app is inactive then, which must not blur the vault).
    public var isAuthenticating = false
    @ObservationIgnored private var leftAt: Date?
    @ObservationIgnored private var visibleViews = 0
    @ObservationIgnored private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public func unlock() {
        isUnlocked = true
        lockedByHand = false
        leftAt = nil
    }

    public func lock() {
        isUnlocked = false
        lockedByHand = true
        leftAt = nil
    }

    /// A vault screen appeared (the vault itself or a document pushed from it).
    public func appeared() {
        visibleViews += 1
        checkReturn()
    }

    /// A vault screen disappeared; when none is left the grace period starts.
    public func disappeared() {
        visibleViews = max(0, visibleViews - 1)
        if visibleViews == 0 {
            markLeft()
            lockedByHand = false
        }
    }

    public func appWentToBackground() { markLeft() }

    public func appBecameActive() {
        if visibleViews > 0 { checkReturn() }
    }

    private func markLeft() {
        if isUnlocked, leftAt == nil { leftAt = now() }
    }

    private func checkReturn() {
        guard let left = leftAt else { return }
        if now().timeIntervalSince(left) >= Self.grace { isUnlocked = false }
        leftAt = nil
    }
}
