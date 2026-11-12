import Foundation

/// Exponential backoff: 5 s, 10 s, 20 s … capped at 600 s (contract §5: 最多到 10 分钟一次). attempt starts at 0.
public nonisolated struct DriveBackoff: Equatable, Sendable, Codable {
    public static let baseDelay: TimeInterval = 5
    public static let maxDelay: TimeInterval = 600

    public var attempt: Int

    public init(attempt: Int = 0) {
        self.attempt = attempt
    }

    public var delay: TimeInterval {
        let exponent = max(0, attempt)
        // 5 * 2^7 = 640 > 600, so anything from 7 up is the cap (and no overflow for huge attempts).
        guard exponent < 7 else { return Self.maxDelay }
        return min(Self.maxDelay, Self.baseDelay * Double(1 << exponent))
    }

    /// attempt += 1, saturating.
    public mutating func fail() {
        if attempt < Int.max { attempt = max(0, attempt) + 1 }
    }

    public mutating func reset() {
        attempt = 0
    }
}
