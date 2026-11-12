import Foundation
public struct MockCryptoHolding: Identifiable {
    public var id: String { symbol }
    public let symbol: String
    public let quantity: Double
    public let avgCost: Double
    public var instId: String { "\(symbol)-USDT" }

    public init(symbol: String, quantity: Double, avgCost: Double) {
        self.symbol = symbol
        self.quantity = quantity
        self.avgCost = avgCost
    }
}
