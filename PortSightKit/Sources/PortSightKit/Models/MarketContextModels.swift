import Foundation

public struct SectorMoneyFlow: Identifiable {
    public let id: String
    public let name: String
    /// Net inflow in USD billions; negative values indicate an outflow.
    public let netInflow: Double

    public init(id: String, name: String, netInflow: Double) {
        self.id = id
        self.name = name
        self.netInflow = netInflow
    }
}

public struct MarketCalendarEvent: Identifiable {
    public let id: String
    public let title: String
    public let category: String
    public let date: Date
    /// An empty set denotes an event that affects the whole market.
    public let symbols: Set<String>

    public init(id: String, title: String, category: String, date: Date, symbols: Set<String>) {
        self.id = id
        self.title = title
        self.category = category
        self.date = date
        self.symbols = symbols
    }
}

public struct RelatedMarketNews: Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let symbols: Set<String>
    public let publishedAt: Date

    public init(id: String, title: String, summary: String, symbols: Set<String>, publishedAt: Date) {
        self.id = id
        self.title = title
        self.summary = summary
        self.symbols = symbols
        self.publishedAt = publishedAt
    }
}

public struct EventCountdown {
    public let days: Int
    public let hours: Int
    public let minutes: Int
    public let seconds: Int

    public init(deadline: Date, now: Date) {
        let remaining = Int(max(0, ceil(deadline.timeIntervalSince(now))))
        days = remaining / 86_400
        hours = remaining % 86_400 / 3_600
        minutes = remaining % 3_600 / 60
        seconds = remaining % 60
    }
}
