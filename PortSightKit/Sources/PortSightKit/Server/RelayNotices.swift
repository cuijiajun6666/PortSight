//
//  RelayNotices.swift
//  PortSightKit
//
//  GET /notices: the messages the Mac mini writes for people (量化保护检查, 日报 / 周报已生成, IBKR 需要重新授权,
//  personal trades …). Once a relay is paired they replace the built-in notices in the bell, on 总览's 需要处理 and
//  in the notice pages (as DemoNotice, so the existing pages show them), and the relay's own /alerts replace the
//  built-in alerts (TerminalDemo). A push whose event_id is a notice id (e.g. "protect:2026-11-11:…") opens that
//  notice. 已读 / 已确认 stay on this device; the app never writes them back.
//

import Foundation
import Observation

// MARK: - Model

/// One GET /notices entry.
public nonisolated struct RelayNotice: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// safety / risk / event / review / trade / data / ops / model / research.
    public var category: String?
    /// info / warning / critical.
    public var severity: String?
    public var title: String?
    public var detail: String?
    /// ISO 8601 UTC.
    public var at: String?
    /// personal / quant / all.
    public var owner: String?
    public var symbols: [String] = []
    public var requires_ack: Bool?
    public var facts: [Fact] = []
    /// Where the notice's button leads (RelayLink); an unknown link is not offered.
    public var link: String?
    public var expires_at: String?

    public nonisolated struct Fact: Codable, Equatable, Sendable {
        public var label: String
        public var value: String
    }

    private enum CodingKeys: String, CodingKey {
        case id, category, severity, title, detail, at, owner, symbols, requires_ack, facts, link, expires_at
    }

    public init(id: String, category: String? = nil, severity: String? = nil, title: String? = nil, detail: String? = nil,
                at: String? = nil, owner: String? = nil, symbols: [String] = [], requires_ack: Bool? = nil,
                facts: [Fact] = [], link: String? = nil, expires_at: String? = nil) {
        self.id = id
        self.category = category
        self.severity = severity
        self.title = title
        self.detail = detail
        self.at = at
        self.owner = owner
        self.symbols = symbols
        self.requires_ack = requires_ack
        self.facts = facts
        self.link = link
        self.expires_at = expires_at
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientString(.id), !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "notice without id")
        }
        self.id = id
        category = c.lenientString(.category)
        severity = c.lenientString(.severity)
        title = c.lenientString(.title)
        detail = c.lenientString(.detail)
        at = c.lenientString(.at)
        owner = c.lenientString(.owner)
        symbols = ((try? c.decodeIfPresent([JournalText].self, forKey: .symbols)) ?? []).compactMap(\.value)
        requires_ack = c.lenientBool(.requires_ack)
        facts = ((try? c.decodeIfPresent([LossyFact].self, forKey: .facts)) ?? []).compactMap(\.fact)
        link = c.lenientString(.link)
        expires_at = c.lenientString(.expires_at)
    }

    private struct LossyFact: Decodable {
        var fact: Fact?
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: FlexibleKey.self),
                  let label = c.string("label", "name"), let value = c.string("value") else { return }
            fact = Fact(label: label, value: value)
        }
    }

    public var date: Date? { at.flatMap(JournalTime.milliseconds).map { Date(timeIntervalSince1970: $0 / 1_000) } }
    public var expiresAt: Date? { expires_at.flatMap(JournalTime.milliseconds).map { Date(timeIntervalSince1970: $0 / 1_000) } }
    public var parsedLink: RelayLink? { RelayLink(link) }
    /// The notice asks the user to re-authorize IBKR.
    public var isIBKRReauth: Bool { parsedLink == .ibkrReauth }
    /// A personal trade or position change: the IBKR account should be read again at once.
    public var isTrade: Bool { category?.lowercased() == "trade" }

    /// 安全 / 风险 / 事件 / 复盘 / 交易 …, the titles the bell's category filter uses.
    public var categoryTitle: String { Self.categoryTitle(category) }

    public static func categoryTitle(_ key: String?) -> String {
        switch key?.lowercased() {
        case "safety": "安全"
        case "risk": "风险"
        case "event": "事件"
        case "review": "复盘"
        case "trade": "交易"
        case "data": "数据"
        case "ops": "运维"
        case "model": "模型"
        case "research": "研究"
        case let other?: other.isEmpty ? "通知" : other
        case nil: "通知"
        }
    }

}

extension RelayNotice {
    /// As the notice type every notice page already shows.
    public func asNotice(now: Date = .now) -> DemoNotice {
        let severity = (severity ?? "info").lowercased()
        var notice = DemoNotice(id: id, title: title ?? "通知", detail: detail ?? "",
                                severity: ["critical", "warning", "info"].contains(severity) ? severity : "info",
                                category: categoryTitle, time: Self.timeText(date, now: now),
                                owner: Self.scope(owner))
        notice.fromRelay = true
        notice.at = date
        notice.requiresAck = requires_ack == true
        notice.link = parsedLink == nil ? nil : link
        notice.facts = facts.map { DemoNoticeFact(label: $0.label, value: $0.value) }
        notice.symbols = symbols
        notice.expiresAt = expiresAt
        return notice
    }

    static func scope(_ owner: String?) -> PortfolioScope {
        switch owner?.lowercased() {
        case "personal": .personal
        case "quant": .quant
        default: .all
        }
    }

    /// "10:34" today, "昨天 21:00", else "11-09 21:00".
    static func timeText(_ date: Date?, now: Date) -> String {
        guard let date else { return "—" }
        let calendar = Calendar.current
        let clock = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        if calendar.isDate(date, inSameDayAs: now) { return clock }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 " + clock
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

/// The notices as cached between launches, newest first.
public nonisolated struct RelayNoticeList: Codable, Equatable, Sendable {
    public var notices: [RelayNotice]

    public init(notices: [RelayNotice]) {
        var seen = Set<String>()
        self.notices = notices.filter { seen.insert($0.id).inserted }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}

/// One page of GET /notices (same paging as /alerts: events, next_cursor, has_more).
nonisolated struct RelayNoticePage: Decodable {
    var events: [RelayNotice] = []
    var next_cursor: String?
    var has_more: Bool?

    private enum CodingKeys: String, CodingKey { case events, notices, next_cursor, has_more }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        let items = (try? c.decodeIfPresent([LossyNotice].self, forKey: .events))
            ?? (try? c.decodeIfPresent([LossyNotice].self, forKey: .notices)) ?? []
        events = items.compactMap(\.notice)
        next_cursor = c.lenientString(.next_cursor)
        has_more = c.lenientBool(.has_more)
    }

    private struct LossyNotice: Decodable {
        var notice: RelayNotice?
        init(from decoder: Decoder) throws { notice = try? RelayNotice(from: decoder) }
    }
}

// MARK: - Links

/// A notice's `link`. Anything else is not offered as a button.
public nonisolated enum RelayLink: Equatable, Hashable, Sendable {
    /// The IBKR re-authorization banner on the home page.
    case ibkrReauth
    /// report:host_daily:<date>: the Mac mini's daily ops report, shown by the 服务器 page (/host).
    case hostDailyReport(date: String)
    /// report:<kind>:<line>:<day>: a line's daily / weekly / monthly report (/reports/latest), the 复盘 page.
    case lineReport(kind: String, line: String, day: String)
    /// journal: the 理由卡 page.
    case journal
    /// asset:<symbol>.
    case asset(symbol: String)

    public init?(_ text: String?) {
        let parts = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let head = parts.first?.lowercased(), !head.isEmpty else { return nil }
        switch head {
        case "ibkr" where parts.count == 2 && parts[1].lowercased() == "reauth":
            self = .ibkrReauth
        case "report" where parts.count == 3 && parts[1].lowercased() == "host_daily" && !parts[2].isEmpty:
            self = .hostDailyReport(date: parts[2])
        case "report" where parts.count == 4 && parts[1...3].allSatisfy({ !$0.isEmpty }):
            self = .lineReport(kind: parts[1].lowercased(), line: parts[2], day: parts[3])
        case "journal" where parts.count == 1:
            self = .journal
        case "asset" where parts.count == 2 && !parts[1].isEmpty:
            self = .asset(symbol: parts[1].uppercased())
        default:
            return nil
        }
    }

    /// The notice page's button.
    public var title: String {
        switch self {
        case .ibkrReauth: "去重新授权"
        case .hostDailyReport: "查看服务器状态"
        case .lineReport(let kind, _, _):
            switch kind {
            case "daily": "查看日报"
            case "weekly": "查看周报"
            case "monthly": "查看月报"
            default: "查看复盘"
            }
        case .journal: "查看理由卡"
        case .asset(let symbol): "查看 " + symbol
        }
    }

    public var icon: String {
        switch self {
        case .ibkrReauth: "person.badge.key"
        case .hostDailyReport: "macmini"
        case .lineReport: "doc.text.magnifyingglass"
        case .journal: "text.document"
        case .asset: "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - Store and the app's lists

public enum RelayNotices {
    /// Notices of the last 7 days, read with each server refresh (at most every 30 s) and kept on disk.
    public static let store = RelayFeedStore<RelayNoticeList>(cacheName: "notices.json", minInterval: 10) { read in
        try await fetch(read)
    }

    /// Pages read per load at most (500 notices each).
    static let maxPages = 10

    static func fetch(_ read: RelayFeedStore<RelayNoticeList>.Reader, now: Date = .now) async throws
        -> RelayFetchResult<RelayNoticeList> {
        let since = ISO8601DateFormatter().string(from: now.addingTimeInterval(-7 * 86_400))
        var query = [URLQueryItem(name: "since", value: since)]
        var all: [RelayNotice] = []
        for _ in 0..<maxPages {
            let data = try await read(.notices, query)
            if let message = RelayAvailability.unavailableMessage(data) { return .unavailable(message) }
            let page = try JSONDecoder().decode(RelayNoticePage.self, from: data)
            all += page.events
            guard page.has_more == true, let cursor = page.next_cursor, !cursor.isEmpty else { break }
            query = [URLQueryItem(name: "cursor", value: cursor)]
        }
        return .document(RelayNoticeList(notices: all))
    }

    /// True while a relay is paired and its data (not the sample) is on screen: the bell, 需要处理 and the notice
    /// pages show the relay's notices and alerts instead of the built-in ones.
    public static var usesRelay: Bool {
        let server = ServerStore.shared
        return server.pairingState != .unpaired && !server.isSample
    }

    /// The relay's notices as DemoNotice (newest first), or nil while the built-in notices apply.
    public static func current(now: Date = .now) -> [DemoNotice]? {
        guard usesRelay else { return nil }
        return (store.document?.notices ?? []).map { $0.asNotice(now: now) }
    }

    public static func notice(id: String) -> RelayNotice? {
        store.document?.notices.first { $0.id == id }
    }

    /// The notice a tapped push announced (its event_id is a notice id), reading /notices once more when it is not
    /// here yet. nil when the push is not a notice (an alert, or no event id).
    public static func notice(for ref: PushEventRef) async -> RelayNotice? {
        guard let id = ref.eventID, !id.isEmpty else { return nil }
        if let known = notice(id: id) { return known }
        // A known alert opens at once, without waiting for /notices.
        guard usesRelay, !ServerStore.shared.knowsEvent(id) else { return nil }
        await store.load(force: true)
        return notice(id: id)
    }
}

// MARK: - Relay alerts in the alert pages

extension HostEvent {
    /// As the alert type the bell and the alert pages show.
    public func asTerminalAlert() -> TerminalAlert {
        let facts = detailFacts.map { $0.label + "：" + $0.value }
        return TerminalAlert(id: id, source: source ?? "Mac mini",
                             category: category.flatMap(AlertCategory.init(rawValue:)) ?? .ops,
                             severity: AlertSeverity(noticeSeverity: severity ?? "info"),
                             title: title ?? id, detail: facts.joined(separator: "，"),
                             at: ServerDates.parse(at) ?? .distantPast)
    }
}
