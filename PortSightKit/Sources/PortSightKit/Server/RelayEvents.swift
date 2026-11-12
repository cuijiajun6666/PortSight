//
//  RelayEvents.swift
//  PortSight
//
//  A tapped push → the relay event it announced. The push (relay quant_system/relay/service.py `push_payload`)
//  carries only `aps.alert` (title, body) and a top-level `event_id`: severity, category, source and details stay
//  off Apple's servers and the lock screen. The app looks the id up in the synced GET /alerts, syncs once if it is
//  not there yet, and otherwise shows the push's own title and body.
//  Event ids are "<kind>@<time>": events with the same part before "@" are the same kind of alert.
//

import Foundation

/// The parts of a tapped push the app needs.
public nonisolated struct PushEventRef: Hashable, Sendable, Identifiable {
    public let eventID: String?
    public let title: String
    public let body: String

    public var id: String { eventID ?? (title + "\n" + body) }

    public init(eventID: String?, title: String, body: String) {
        self.eventID = eventID
        self.title = title
        self.body = body
    }

    /// nil when the notification is not a PortSight push (no `aps` alert and no `event_id`).
    public init?(userInfo: [AnyHashable: Any]) {
        let aps = userInfo["aps"] as? [String: Any]
        var title = "", body = ""
        if let alert = aps?["alert"] as? [String: Any] {
            title = alert["title"] as? String ?? ""
            body = alert["body"] as? String ?? ""
        } else if let alert = aps?["alert"] as? String {
            body = alert
        }
        let eventID = (userInfo["event_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard eventID != nil || !title.isEmpty || !body.isEmpty else { return nil }
        self.init(eventID: eventID, title: title, body: body)
    }

    /// "forward_lockbox_audit@2026-11-09T12:00Z" → "forward_lockbox_audit". Host alerts (relay host_status.py) are
    /// "host:<key>:<since>", plus ":<severity>" when they escalate and ":recovered" when they clear, so
    /// "host:hb:forward15m:20261103T014000Z:critical:recovered" → "host:hb:forward15m". Other ids are their own kind.
    public static func kind(of eventID: String) -> String {
        if let at = eventID.firstIndex(of: "@") { return String(eventID[..<at]) }
        var parts = eventID.split(separator: ":", omittingEmptySubsequences: false)
        while parts.count > 1, let last = parts.last, Self.stateSuffixes.contains(String(last)) { parts.removeLast() }
        if parts.count > 1, let last = parts.last, isTimestamp(last) {
            parts.removeLast()
            return parts.joined(separator: ":")
        }
        return eventID
    }

    /// Endings a host alert's id gets after its time: an escalation's severity, or the recovery.
    private static let stateSuffixes: Set<String> = ["critical", "warning", "info", "recovered"]

    /// "20261103T014000Z", "2026-11-03T01:40Z", "1794000000": digits first, then only digits and time marks.
    private static func isTimestamp(_ text: Substring) -> Bool {
        text.count >= 8 && text.first?.isNumber == true && text.allSatisfy { $0.isNumber || "TZ-.+".contains($0) }
    }
}

extension PushEventRef {
    /// Push titles start with the severity ("严重：…"); pages show it in the severity capsule instead.
    public var headline: String {
        for prefix in ["严重：", "警告：", "信息：", "严重:", "警告:", "信息:"] where title.hasPrefix(prefix) {
            return String(title.dropFirst(prefix.count))
        }
        return title.isEmpty ? "告警" : title
    }

    /// The severity the push title starts with (info when it names none).
    public var severity: AlertSeverity {
        if title.hasPrefix("严重") { return .critical }
        if title.hasPrefix("警告") { return .warning }
        return .info
    }
}

/// Any JSON value, for an event's free-form `detail` object.
public nonisolated enum RelayJSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), array([RelayJSONValue]), object([String: RelayJSONValue]), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([RelayJSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: RelayJSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    /// One line for a fact row.
    public var displayText: String {
        switch self {
        case .string(let v): return v
        case .number(let v):
            return v.rounded() == v && abs(v) < 1e15 ? String(Int64(v)) : v.formatted(.number.precision(.fractionLength(0...4)))
        case .bool(let v): return v ? "是" : "否"
        case .null: return "—"
        case .array(let v): return v.map(\.displayText).joined(separator: "、")
        case .object(let v): return v.keys.sorted().map { "\($0): \(v[$0]!.displayText)" }.joined(separator: "，")
        }
    }
}

extension HostEvent {
    /// Kind of alert ("<kind>@<time>"), shared by every occurrence.
    public var kind: String { PushEventRef.kind(of: id) }

    /// `detail` as label/value pairs, keys sorted.
    public var detailFacts: [(label: String, value: String)] {
        (detail ?? [:]).keys.sorted().map { ($0, detail![$0]!.displayText) }
    }
}

/// What looking up a tapped push's event found. Anything but `found` shows the push's own title and body.
public enum RelayEventLookup {
    case found(HostEvent)
    /// The relay answered, but has no event with that id.
    case notFound
    /// The relay could not be read (offline, or it needs pairing again).
    case unavailable
    case notPaired
    /// The push carries no event_id (for example the evening digest).
    case noEvent

    public var event: HostEvent? {
        if case .found(let event) = self { return event }
        return nil
    }

    /// The note under a page that shows the push's own text.
    public var fallbackNote: String? {
        switch self {
        case .found, .noEvent: nil
        case .notFound: "服务器上没有找到这条告警的详情，显示的是推送的内容。"
        case .unavailable: "暂时读不到服务器上的告警，显示的是推送的内容。"
        case .notPaired: "还没有配对服务器，显示的是推送的内容。"
        }
    }
}

extension ServerStore {
    /// The relay event a tapped push points at: the synced /alerts first, then one fresh sync of /alerts.
    public func lookUpEvent(_ ref: PushEventRef) async -> RelayEventLookup {
        guard let id = ref.eventID else { return .noEvent }
        if let known = knownEvent(id) { return .found(known) }
        guard isPaired else { return .notPaired }
        guard let fetched = await syncAlerts() else { return .unavailable }
        return fetched.first { $0.id == id }.map { .found($0) } ?? .notFound
    }

    /// Earlier occurrences of the same kind of alert, newest first, without the event itself.
    public func history(of event: HostEvent) -> [HostEvent] {
        let all = syncedEvents + events + (host?.alerts_recent ?? [])
        var seen = Set<String>()
        return all.filter { $0.kind == event.kind && $0.id != event.id && seen.insert($0.id).inserted }
            .sorted { ($0.at ?? "") > ($1.at ?? "") }
    }

    /// The id is an alert this device already has (so a push with it is an alert, not a notice).
    public func knowsEvent(_ id: String) -> Bool { knownEvent(id) != nil }

    private func knownEvent(_ id: String) -> HostEvent? {
        syncedEvents.first { $0.id == id } ?? events.first { $0.id == id } ?? host?.alerts_recent?.first { $0.id == id }
    }
}
