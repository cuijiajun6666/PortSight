//
//  RelayMarket.swift
//  PortSightKit
//
//  GET /calendar (earnings and macro events for the next 14 days) and GET /news (news about held symbols) from the
//  Mac mini. Once a relay is paired they replace the built-in calendar and news on 总览 / 资产; until then the
//  built-in ones stay. An empty calendar is normal ("未来 14 天没有重要事件"), and the relay's `message` (e.g. why
//  earnings dates are missing) is shown under the list. /news answers 404 until it opens: "相关新闻尚未开放".
//

import Foundation

// MARK: - Calendar

public nonisolated struct RelayCalendar: Codable, Equatable, Sendable {
    public var as_of: String?
    public var days: Int?
    public var covers_until: String?
    public var calendar_updated: String?
    public var earnings_available: Bool?
    /// Shown under the list, e.g. why there are no earnings dates yet.
    public var message: String?
    public var events: [RelayCalendarEvent] = []

    private enum CodingKeys: String, CodingKey {
        case as_of, days, covers_until, calendar_updated, earnings_available, message, events
    }

    public init(events: [RelayCalendarEvent] = [], message: String? = nil, earnings_available: Bool? = nil) {
        self.events = events
        self.message = message
        self.earnings_available = earnings_available
    }

    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        as_of = c.lenientString(.as_of)
        days = c.lenientDouble(.days).map { Int($0) }
        covers_until = c.lenientString(.covers_until)
        calendar_updated = c.lenientString(.calendar_updated)
        earnings_available = c.lenientBool(.earnings_available)
        message = c.lenientString(.message).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        events = ((try? c.decodeIfPresent([Lossy<RelayCalendarEvent>].self, forKey: .events)) ?? []).compactMap(\.value)
    }
}

public nonisolated struct RelayCalendarEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// earnings / macro / dividend / other.
    public var category: String?
    /// ISO 8601 UTC.
    public var at: String?
    /// pre / post / intraday / unknown (earnings before or after the session).
    public var session: String?
    public var symbols: [String] = []
    public var source: String?

    private enum CodingKeys: String, CodingKey { case id, title, category, at, session, symbols, source }

    public init(id: String, title: String, category: String? = nil, at: String? = nil, session: String? = nil,
                symbols: [String] = [], source: String? = nil) {
        self.id = id
        self.title = title
        self.category = category
        self.at = at
        self.session = session
        self.symbols = symbols
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let title = c.lenientString(.title), !title.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .title, in: c, debugDescription: "event without title")
        }
        self.title = title
        at = c.lenientString(.at)
        id = c.lenientString(.id) ?? (title + "|" + (at ?? ""))
        category = c.lenientString(.category)
        session = c.lenientString(.session)
        symbols = ((try? c.decodeIfPresent([JournalText].self, forKey: .symbols)) ?? []).compactMap(\.value)
        source = c.lenientString(.source)
    }

    public var date: Date? { at.flatMap(JournalTime.milliseconds).map { Date(timeIntervalSince1970: $0 / 1_000) } }

    /// 公司财报 / 宏观事件 / 分红 / 事件.
    public var categoryTitle: String {
        switch category?.lowercased() {
        case "earnings": "公司财报"
        case "macro": "宏观事件"
        case "dividend": "分红"
        default: "事件"
        }
    }

    /// 盘前 / 盘后 / 盘中, or nil.
    public var sessionTitle: String? {
        switch session?.lowercased() {
        case "pre": "盘前"
        case "post": "盘后"
        case "intraday": "盘中"
        default: nil
        }
    }
}

extension RelayCalendarEvent {
    /// As the event type the calendar cards show.
    public var asMarketEvent: MarketCalendarEvent? {
        guard let date else { return nil }
        return MarketCalendarEvent(id: id, title: title + (sessionTitle.map { "（\($0)）" } ?? ""),
                                   category: categoryTitle, date: date, symbols: Set(symbols))
    }
}

// MARK: - News

public nonisolated struct RelayNewsList: Codable, Equatable, Sendable {
    public var items: [RelayNewsItem]

    private enum CodingKeys: String, CodingKey { case items, news, events }

    public init(items: [RelayNewsItem]) { self.items = items }

    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            items = []
            return
        }
        let lists = [CodingKeys.items, .news, .events].lazy.compactMap {
            try? c.decodeIfPresent([Lossy<RelayNewsItem>].self, forKey: $0)
        }
        items = (lists.first ?? []).compactMap(\.value)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(items, forKey: .items)
    }
}

public nonisolated struct RelayNewsItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String?
    public var symbols: [String] = []
    public var published_at: String?
    public var source: String?
    public var url: String?

    private enum CodingKeys: String, CodingKey { case id, title, summary, symbols, published_at, source, url }

    public init(id: String, title: String, summary: String? = nil, symbols: [String] = [], published_at: String? = nil,
                source: String? = nil, url: String? = nil) {
        self.id = id
        self.title = title
        self.summary = summary
        self.symbols = symbols
        self.published_at = published_at
        self.source = source
        self.url = url
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let title = c.lenientString(.title), !title.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .title, in: c, debugDescription: "news without title")
        }
        self.title = title
        id = c.lenientString(.id) ?? title
        summary = c.lenientString(.summary)
        symbols = ((try? c.decodeIfPresent([JournalText].self, forKey: .symbols)) ?? []).compactMap(\.value)
        published_at = c.lenientString(.published_at)
        source = c.lenientString(.source)
        url = c.lenientString(.url)
    }

    public var date: Date? { published_at.flatMap(JournalTime.milliseconds).map { Date(timeIntervalSince1970: $0 / 1_000) } }
}

extension RelayNewsItem {
    public var asMarketNews: RelatedMarketNews {
        RelatedMarketNews(id: id, title: title, summary: summary ?? "", symbols: Set(symbols),
                          publishedAt: date ?? .distantPast)
    }
}

/// Decodes an element or nothing, so one odd entry never drops a list.
nonisolated struct Lossy<Value: Decodable>: Decodable {
    var value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

// MARK: - Stores and what the cards show

public enum RelayMarket {
    /// The next 14 days; read with each server refresh, at most every 5 minutes.
    public static let calendar = RelayFeedStore<RelayCalendar>(cacheName: "calendar.json", minInterval: 300) { read in
        let data = try await read(.calendar, [URLQueryItem(name: "days", value: "14")])
        if let message = RelayAvailability.unavailableMessage(data) { return .unavailable(message) }
        return .document(try JSONDecoder().decode(RelayCalendar.self, from: data))
    }

    public static let news = RelayFeedStore<RelayNewsList>(cacheName: "news.json", minInterval: 300) { read in
        let data = try await read(.news, [URLQueryItem(name: "limit", value: "20")])
        if let message = RelayAvailability.unavailableMessage(data) { return .unavailable(message) }
        return .document(try JSONDecoder().decode(RelayNewsList.self, from: data))
    }

    /// What a calendar or news card shows: items, or a line instead of them, and notes under them.
    public struct CardState<Item> {
        public var items: [Item]
        /// Shown instead of the items: nothing to show (empty), not open yet, not readable…
        public var emptyTitle: String?
        public var emptyDetail: String?
        /// The relay's own note (e.g. why earnings dates are missing).
        public var note: String?
        /// "离线：显示 HH:mm 保存的…" while the items are a saved copy.
        public var savedNote: String?
        public var isLoading = false
        /// True when the items are the built-in ones (no relay paired).
        public var isBuiltIn = false
    }

    /// The calendar for `scope`, soonest first: the relay's next 14 days, or the built-in events before pairing.
    public static func calendarState(scope: PortfolioScope, now: Date = .now) -> CardState<MarketCalendarEvent> {
        guard RelayNotices.usesRelay else {
            return CardState(items: DemoMarketContext.events(for: scope), isBuiltIn: true)
        }
        let store = calendar
        guard let document = store.document else {
            // Nothing read from the relay (yet): the built-in events fill in.
            return CardState(items: DemoMarketContext.events(for: scope), isLoading: store.phase.isLoading, isBuiltIn: true)
        }
        // The relay already lists only what concerns the holdings; nothing is filtered by scope here.
        let items = document.events.compactMap(\.asMarketEvent).filter { $0.date >= now.addingTimeInterval(-3_600) }
            .sorted { $0.date < $1.date }
        return CardState(items: items, emptyTitle: items.isEmpty ? "未来 14 天没有重要事件" : nil, note: document.message,
                         savedNote: savedNote(store, what: "日历"))
    }

    /// The next event at or after `date`, for the countdown card.
    public static func nextEvent(scope: PortfolioScope, after date: Date) -> MarketCalendarEvent? {
        calendarState(scope: scope, now: date).items.first { $0.date >= date }
    }

    /// News for `scope`, newest first: the relay's, or the built-in ones before pairing.
    public static func newsState(scope: PortfolioScope) -> CardState<RelatedMarketNews> {
        guard RelayNotices.usesRelay else {
            return CardState(items: DemoMarketContext.news(for: scope), isBuiltIn: true)
        }
        let store = news
        guard let document = store.document else {
            // /news is not open yet (or not read): the built-in news fill in.
            return CardState(items: DemoMarketContext.news(for: scope), isLoading: store.phase.isLoading, isBuiltIn: true)
        }
        let items = document.items.map(\.asMarketNews).sorted { $0.publishedAt > $1.publishedAt }
        return CardState(items: items, emptyTitle: items.isEmpty ? "暂时没有相关新闻" : nil,
                         savedNote: savedNote(store, what: "新闻"))
    }

    static func savedNote<Document>(_ store: RelayFeedStore<Document>, what: String) -> String? {
        guard store.isSaved, let readAt = store.readAt else { return nil }
        return "离线：显示 \(RelayNotice.timeText(readAt, now: .now)) 保存的\(what)"
    }
}
