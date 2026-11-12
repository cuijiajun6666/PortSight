//
//  ServerModels.swift
//  PortSight
//
//  GET /host on the quant relay: quant_system/monitoring/host_status.py latest.json, plus the relay's age check.
//  Every field is optional so a newer or older server never breaks decoding; missing values show as "—".
//

import Foundation

public struct HostStatus: Codable, Equatable {
    /// false when the relay has no host status yet ({"available": false, "message": ...}); the page then shows
    /// 暂无数据 instead of empty values.
    public var available: Bool?
    public var message: String?
    public var as_of: String?
    public var stale_after_minutes: Double?
    public var relay_age_seconds: Double?
    public var stale: Bool?
    public var summary: HostSummary?
    public var host: HostMachine?
    public var disks: [String: HostDisk?]?
    public var launchd: HostLaunchd?
    public var heartbeats: [HostHeartbeat]?
    public var queue: HostQueue?
    public var collector_health: HostCollectorReport?
    public var deadman: HostDeadman?
    public var push: HostPush?
    public var alerts_active: [HostActiveAlert]?
    public var alerts_recent: [HostEvent]?
    public var history: [HostHistoryPoint]?

    public init(available: Bool? = nil, message: String? = nil, as_of: String? = nil, stale_after_minutes: Double? = nil, relay_age_seconds: Double? = nil, stale: Bool? = nil, summary: HostSummary? = nil, host: HostMachine? = nil, disks: [String: HostDisk?]? = nil, launchd: HostLaunchd? = nil, heartbeats: [HostHeartbeat]? = nil, queue: HostQueue? = nil, collector_health: HostCollectorReport? = nil, deadman: HostDeadman? = nil, push: HostPush? = nil, alerts_active: [HostActiveAlert]? = nil, alerts_recent: [HostEvent]? = nil, history: [HostHistoryPoint]? = nil) {
        self.available = available
        self.message = message
        self.as_of = as_of
        self.stale_after_minutes = stale_after_minutes
        self.relay_age_seconds = relay_age_seconds
        self.stale = stale
        self.summary = summary
        self.host = host
        self.disks = disks
        self.launchd = launchd
        self.heartbeats = heartbeats
        self.queue = queue
        self.collector_health = collector_health
        self.deadman = deadman
        self.push = push
        self.alerts_active = alerts_active
        self.alerts_recent = alerts_recent
        self.history = history
    }

    /// The document carries host data (anything but {"available": false}).
    public var hasData: Bool { available != false }
}

public struct HostSummary: Codable, Equatable {
    public var state: String?
    public var active_alerts: Int?
    public var heartbeats_ok: Int?
    public var heartbeats_problem: Int?

    public init(state: String? = nil, active_alerts: Int? = nil, heartbeats_ok: Int? = nil, heartbeats_problem: Int? = nil) {
        self.state = state
        self.active_alerts = active_alerts
        self.heartbeats_ok = heartbeats_ok
        self.heartbeats_problem = heartbeats_problem
    }
}

public struct HostMachine: Codable, Equatable {
    public var hostname: String?
    public var cpu_count: Int?
    public var load: HostLoad?
    public var memory: HostMemory?
    public var thermal: HostThermal?
    public var power: HostPower?
    public var boot_at: String?
    public var uptime_hours: Double?

    public init(hostname: String? = nil, cpu_count: Int? = nil, load: HostLoad? = nil, memory: HostMemory? = nil, thermal: HostThermal? = nil, power: HostPower? = nil, boot_at: String? = nil, uptime_hours: Double? = nil) {
        self.hostname = hostname
        self.cpu_count = cpu_count
        self.load = load
        self.memory = memory
        self.thermal = thermal
        self.power = power
        self.boot_at = boot_at
        self.uptime_hours = uptime_hours
    }
}

public struct HostLoad: Codable, Equatable {
    public var m1: Double?
    public var m5: Double?
    public var m15: Double?
    public var per_core_5m: Double?

    public init(m1: Double? = nil, m5: Double? = nil, m15: Double? = nil, per_core_5m: Double? = nil) {
        self.m1 = m1
        self.m5 = m5
        self.m15 = m15
        self.per_core_5m = per_core_5m
    }
}

public struct HostMemory: Codable, Equatable {
    public var total_gb: Double?
    public var pressure: String?
    public var free_pct: Double?
    public var swap_used_gb: Double?
    public var swap_total_gb: Double?

    public init(total_gb: Double? = nil, pressure: String? = nil, free_pct: Double? = nil, swap_used_gb: Double? = nil, swap_total_gb: Double? = nil) {
        self.total_gb = total_gb
        self.pressure = pressure
        self.free_pct = free_pct
        self.swap_used_gb = swap_used_gb
        self.swap_total_gb = swap_total_gb
    }
}

public struct HostThermal: Codable, Equatable {
    public var available: Bool?
    /// pmset's thermal warning level; set (not empty) once macOS has slowed the machine down because of heat.
    public var thermal_warning: String?
    public var performance_warning: String?
    public var cpu_speed_limit: Int?
    /// Average CPU / GPU temperature in °C (one decimal) from macmon; null when macmon could not be read.
    public var cpu_temp_c: Double?
    public var gpu_temp_c: Double?

    public init(available: Bool? = nil, thermal_warning: String? = nil, performance_warning: String? = nil, cpu_speed_limit: Int? = nil, cpu_temp_c: Double? = nil, gpu_temp_c: Double? = nil) {
        self.available = available
        self.thermal_warning = thermal_warning
        self.performance_warning = performance_warning
        self.cpu_speed_limit = cpu_speed_limit
        self.cpu_temp_c = cpu_temp_c
        self.gpu_temp_c = gpu_temp_c
    }
}

/// How hot a CPU or GPU reading is: under 85 °C normal, 85–95 °C warm (yellow), over 95 °C hot (red).
public nonisolated enum TemperatureLevel: Int, Comparable, Sendable {
    case normal, warm, hot

    public init(celsius: Double) {
        self = celsius > 95 ? .hot : celsius >= 85 ? .warm : .normal
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Said next to a reading, so the level never rests on colour alone.
    public var word: String {
        switch self {
        case .normal: "正常"
        case .warm: "偏高"
        case .hot: "过高"
        }
    }
}

extension HostThermal {
    /// "52.5°C", or "—" when there is no reading.
    public static func text(_ celsius: Double?) -> String {
        guard let celsius, celsius.isFinite else { return "—" }
        return String(format: "%.1f°C", celsius)
    }

    public static func level(_ celsius: Double?) -> TemperatureLevel? {
        guard let celsius, celsius.isFinite else { return nil }
        return TemperatureLevel(celsius: celsius)
    }

    public var cpuLevel: TemperatureLevel? { Self.level(cpu_temp_c) }
    public var gpuLevel: TemperatureLevel? { Self.level(gpu_temp_c) }

    /// The hotter of the two readings (nil when neither was read).
    public var hottest: TemperatureLevel? { [cpuLevel, gpuLevel].compactMap { $0 }.max() }

    /// The readings at 85 °C or more, hottest first, e.g. ("GPU", 96.2, .hot).
    public var warmReadings: [(name: String, celsius: Double, level: TemperatureLevel)] {
        [("CPU", cpu_temp_c), ("GPU", gpu_temp_c)]
            .compactMap { name, celsius -> (name: String, celsius: Double, level: TemperatureLevel)? in
                guard let level = Self.level(celsius), level >= .warm, let celsius else { return nil }
                return (name, celsius, level)
            }
            .sorted { $0.celsius > $1.celsius }
    }

    /// macOS has recorded a thermal warning: the machine is already being slowed down because of heat.
    public var overheated: Bool {
        !(thermal_warning?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

public struct HostPower: Codable, Equatable {
    public var source: String?
    public var kind: String?
    public var percent: Int?

    public init(source: String? = nil, kind: String? = nil, percent: Int? = nil) {
        self.source = source
        self.kind = kind
        self.percent = percent
    }
}

/// A volume (path, mounted, free_gb, ...) or the local-fallback counters (files, mb, blocked).
public struct HostDisk: Codable, Equatable {
    public var path: String?
    public var mounted: Bool?
    public var free_gb: Double?
    public var total_gb: Double?
    public var used_pct: Double?
    public var files: Int?
    public var mb: Double?
    public var blocked: Int?

    public init(path: String? = nil, mounted: Bool? = nil, free_gb: Double? = nil, total_gb: Double? = nil, used_pct: Double? = nil, files: Int? = nil, mb: Double? = nil, blocked: Int? = nil) {
        self.path = path
        self.mounted = mounted
        self.free_gb = free_gb
        self.total_gb = total_gb
        self.used_pct = used_pct
        self.files = files
        self.mb = mb
        self.blocked = blocked
    }
}

public struct HostLaunchd: Codable, Equatable {
    public var available: Bool?
    public var jobs: [String: HostJob]?

    public init(available: Bool? = nil, jobs: [String: HostJob]? = nil) {
        self.available = available
        self.jobs = jobs
    }
}

public struct HostJob: Codable, Equatable {
    public var group: String?
    public var schedule: String?
    public var daemon: Bool?
    public var loaded: Bool?
    public var pid: Int?
    public var last_exit: String?
    public var state: String?

    public init(group: String? = nil, schedule: String? = nil, daemon: Bool? = nil, loaded: Bool? = nil, pid: Int? = nil, last_exit: String? = nil, state: String? = nil) {
        self.group = group
        self.schedule = schedule
        self.daemon = daemon
        self.loaded = loaded
        self.pid = pid
        self.last_exit = last_exit
        self.state = state
    }
}

public struct HostHeartbeat: Codable, Equatable, Identifiable {
    public var name: String
    public var kind: String?
    public var label: String?
    public var last_beat: String?
    public var age_min: Double?
    public var warn_min: Double?
    public var crit_min: Double?
    public var state: String?
    public var phase: String?
    public var status: String?
    public var valid_until: String?
    public var behind: Bool?
    public var last_session: String?
    public var expected_session: String?
    public var id: String { name }

    public init(name: String, kind: String? = nil, label: String? = nil, last_beat: String? = nil, age_min: Double? = nil, warn_min: Double? = nil, crit_min: Double? = nil, state: String? = nil, phase: String? = nil, status: String? = nil, valid_until: String? = nil, behind: Bool? = nil, last_session: String? = nil, expected_session: String? = nil) {
        self.name = name
        self.kind = kind
        self.label = label
        self.last_beat = last_beat
        self.age_min = age_min
        self.warn_min = warn_min
        self.crit_min = crit_min
        self.state = state
        self.phase = phase
        self.status = status
        self.valid_until = valid_until
        self.behind = behind
        self.last_session = last_session
        self.expected_session = expected_session
    }
}

public struct HostQueue: Codable, Equatable {
    public struct Lock: Codable, Equatable {
        public var owner: String?
        public var pid: Int?
        public var alive: Bool?
        public var since: String?
        public var held_hours: Double?
        public var stale: Bool?

        public init(owner: String? = nil, pid: Int? = nil, alive: Bool? = nil, since: String? = nil, held_hours: Double? = nil, stale: Bool? = nil) {
            self.owner = owner
            self.pid = pid
            self.alive = alive
            self.since = since
            self.held_hours = held_hours
            self.stale = stale
        }
    }
    public struct Pause: Codable, Equatable { var since: String? }
    public struct StopFile: Codable, Equatable, Identifiable {
        public var name: String
        public var `where`: String?
        public var since: String?
        public var id: String { (self.where ?? "") + "/" + name }

        public init(name: String, `where`: String? = nil, since: String? = nil) {
            self.name = name
            self.where = `where`
            self.since = since
        }
    }
    public var heavy_lock: Lock?
    public var heavy_pause: Pause?
    public var stop_files: [StopFile]?

    public init(heavy_lock: Lock? = nil, heavy_pause: Pause? = nil, stop_files: [StopFile]? = nil) {
        self.heavy_lock = heavy_lock
        self.heavy_pause = heavy_pause
        self.stop_files = stop_files
    }
}

public struct HostCollectorReport: Codable, Equatable {
    public var available: Bool?
    public var generated_at: String?
    public var age_min: Double?
    public var alerts: [String]?
    public var alert_count: Int?

    public init(available: Bool? = nil, generated_at: String? = nil, age_min: Double? = nil, alerts: [String]? = nil, alert_count: Int? = nil) {
        self.available = available
        self.generated_at = generated_at
        self.age_min = age_min
        self.alerts = alerts
        self.alert_count = alert_count
    }
}

public struct HostDeadman: Codable, Equatable {
    public var enabled: Bool?
    public var last_ok: String?
    public var last_attempt: String?
    public var consecutive_failures: Int?
    public var last_result: String?

    public init(enabled: Bool? = nil, last_ok: String? = nil, last_attempt: String? = nil, consecutive_failures: Int? = nil, last_result: String? = nil) {
        self.enabled = enabled
        self.last_ok = last_ok
        self.last_attempt = last_attempt
        self.consecutive_failures = consecutive_failures
        self.last_result = last_result
    }
}

public struct HostPush: Codable, Equatable {
    public var apns_enabled: Bool?

    public init(apns_enabled: Bool? = nil) {
        self.apns_enabled = apns_enabled
    }
}

public struct HostActiveAlert: Codable, Equatable, Identifiable {
    public var key: String
    public var severity: String?
    public var title: String?
    public var since: String?
    public var id: String { key }

    public init(key: String, severity: String? = nil, title: String? = nil, since: String? = nil) {
        self.key = key
        self.severity = severity
        self.title = title
        self.since = since
    }
}

/// A relay event (GET /alerts) or a host-status outbox event; `detail` is not decoded (free text stays on the server).
public struct HostEvent: Codable, Equatable, Identifiable {
    public var id: String
    public var source: String?
    public var category: String?
    public var severity: String?
    public var title: String?
    public var at: String?
    /// Free-form facts about the event (may be `{}`); a value of another type is ignored, not a decoding error.
    public var detail: [String: RelayJSONValue]?

    public init(id: String, source: String? = nil, category: String? = nil, severity: String? = nil, title: String? = nil,
                at: String? = nil, detail: [String: RelayJSONValue]? = nil) {
        self.id = id
        self.source = source
        self.category = category
        self.severity = severity
        self.title = title
        self.at = at
        self.detail = detail
    }

    private enum CodingKeys: String, CodingKey { case id, source, category, severity, title, at, detail }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        severity = try? c.decodeIfPresent(String.self, forKey: .severity)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        at = try? c.decodeIfPresent(String.self, forKey: .at)
        detail = try? c.decodeIfPresent([String: RelayJSONValue].self, forKey: .detail)
    }
}

public struct HostAlertPage: Codable {
    public var events: [HostEvent]
    public var next_cursor: String?
    public var has_more: Bool?

    public init(events: [HostEvent], next_cursor: String? = nil, has_more: Bool? = nil) {
        self.events = events
        self.next_cursor = next_cursor
        self.has_more = has_more
    }
}

/// history rows are [at, load5, mem_free_pct] arrays.
public struct HostHistoryPoint: Codable, Equatable {
    public var at: String
    public var load5: Double?
    public var memFreePct: Double?

    public init(at: String, load5: Double?, memFreePct: Double?) {
        self.at = at; self.load5 = load5; self.memFreePct = memFreePct
    }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        at = try c.decode(String.self)
        load5 = c.isAtEnd ? nil : try c.decodeIfPresent(Double.self)
        memFreePct = c.isAtEnd ? nil : try c.decodeIfPresent(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(at)
        try c.encode(load5)
        try c.encode(memFreePct)
    }
}

public enum ServerDates {
    /// ISO 8601 from Python: "2026-11-03T02:00:00Z", "...+00:00", with or without microseconds.
    public static func parse(_ value: String?) -> Date? {
        guard var s = value, !s.isEmpty else { return nil }
        if let r = s.range(of: #"\.\d+"#, options: .regularExpression) { s.removeSubrange(r) }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    public static func clock(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M月d日 HH:mm"
        return f.string(from: date)
    }

    public static func age(minutes: Double?) -> String {
        guard let m = minutes else { return "—" }
        if m < 1 { return "刚刚" }
        if m < 120 { return "\(Int(m.rounded())) 分钟前" }
        if m < 48 * 60 { return String(format: "%.1f 小时前", m / 60) }
        return String(format: "%.1f 天前", m / 1440)
    }
}

/// How old the newest heartbeat is, measured with the phone's own clock (works when the relay is unreachable).
public struct ServerFreshness: Equatable {
    public enum State: Equatable { case unknown, fresh, stale }
    public var state: State
    public var lastBeat: Date?
    public var ageMinutes: Double?

    public static func evaluate(asOf: String?, now: Date, staleAfterMinutes: Double) -> ServerFreshness {
        guard let beat = ServerDates.parse(asOf) else { return ServerFreshness(state: .unknown, lastBeat: nil, ageMinutes: nil) }
        let age = max(0, now.timeIntervalSince(beat) / 60)
        return ServerFreshness(state: age > staleAfterMinutes ? .stale : .fresh, lastBeat: beat, ageMinutes: age)
    }

    public init(state: State, lastBeat: Date? = nil, ageMinutes: Double? = nil) {
        self.state = state
        self.lastBeat = lastBeat
        self.ageMinutes = ageMinutes
    }
}
