//
//  DemoTerminalData.swift
//  PortSight
//
//  Fictional fixtures for the terminal sections that have no data source yet (trading lines, relay alerts,
//  cloud, private AI, remote entry). Field names follow the relay plan (UNIFIED_TERMINAL_PLAN.md §3.2) so the
//  pages can switch to real projections later. Nothing here describes a real account, machine or model.
//

import Foundation
import Combine

/// The shared information architecture (plan §0.1). Each app decides where a section lives in its own shell.
public enum TerminalSection: String, CaseIterable, Identifiable {
    case overview, assets, trading, alerts, server, cloud, ai, remote, settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: "总览"
        case .assets: "资产"
        case .trading: "交易"
        case .alerts: "告警"
        case .server: "服务器"
        case .cloud: "云盘"
        case .ai: "AI"
        case .remote: "远程"
        case .settings: "设置"
        }
    }

    public var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .assets: "chart.pie"
        case .trading: "arrow.left.arrow.right.circle"
        case .alerts: "bell"
        case .server: "macmini"
        case .cloud: "photo.stack"
        case .ai: "brain"
        case .remote: "rectangle.on.rectangle"
        case .settings: "gearshape"
        }
    }

    /// Every section symbol has a real filled counterpart, not just a tint change.
    public var selectedIcon: String { icon + ".fill" }

    public var subtitle: String {
        switch self {
        case .overview: "资产、策略和服务器，一眼看全。"
        case .assets: "全部、美股与加密，按账户分开。"
        case .trading: "每条线路的阶段、结果与复盘。"
        case .alerts: "按严重程度和类别筛选全部告警。"
        case .server: "Mac mini 的负载、磁盘与心跳。"
        case .cloud: "照片库与存储空间。"
        case .ai: "资料问答、值班建议与每日复盘。"
        case .remote: "一键回到 Mac mini 的桌面。"
        case .settings: "数据源、推送与显示。"
        }
    }
}

/// Placeholder origin used everywhere a Tailscale name will go (plan §5: never a real address).
public enum TerminalPlaceholders {
    public static let host = "mac-mini.xxxx.ts.net"
    public static let relay = "https://\(host)"
    public static let immich = "https://\(host):10000"
    public static let aiConsole = "https://\(host):8443"
    public static let screenSharing = "vnc://\(host)"
}

// MARK: - Trading lines

public enum TradingMode: String, CaseIterable, Identifiable {
    case shadow, paper, live
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .shadow: "影子"
        case .paper: "模拟盘"
        case .live: "实盘"
        }
    }
    public var detail: String {
        switch self {
        case .shadow: "只记录信号，不下单"
        case .paper: "模拟账户成交"
        case .live: "真实账户成交"
        }
    }
}

public enum TerminalState: String {
    case ok, warning, critical, idle, pending

    public var title: String {
        switch self {
        case .ok: "正常"
        case .warning: "注意"
        case .critical: "严重"
        case .idle: "未运行"
        case .pending: "尚未接入"
        }
    }
}

public struct TradingStage: Identifiable {
    public let name: String
    public let state: TerminalState
    public let note: String
    public var id: String { name }
}

public struct TradingSleeve: Identifiable {
    public let name: String
    public let mode: TradingMode
    public let weight: Double
    public let returnPct: Double
    public var id: String { name }
}

public struct TradingReportPoint: Identifiable {
    public let date: Date
    public let equity: Double
    public let benchmark: Double
    public var id: Date { date }
}

public struct TradingReport {
    public let type: String
    public let summary: String
    public let returnPct: Double
    public let benchmarkPct: Double
    public let maxDrawdown: Double
    public let turnover: Double
    public let costBps: Double
    public let points: [TradingReportPoint]
}

public struct TradingLine: Identifiable {
    public let id: String
    public let title: String
    public let caption: String
    public let icon: String
    public let mode: TradingMode
    public let state: TerminalState
    public let lastRun: Date
    public let lastResult: String
    public let nextRun: Date?
    public let scale: Double
    /// Go-live checklist (上线检验): passed of total.
    public let checksPassed: Int
    public let checksTotal: Int
    public let stages: [TradingStage]
    public let sleeves: [TradingSleeve]
    public let daily: TradingReport
    public let weekly: TradingReport
    public var readiness: Double { checksTotal == 0 ? 0 : Double(checksPassed) / Double(checksTotal) }
}

// MARK: - Relay alerts

public enum AlertSeverity: String, CaseIterable, Identifiable {
    case critical, warning, info
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .critical: "严重"
        case .warning: "警告"
        case .info: "信息"
        }
    }
    public var icon: String {
        switch self {
        case .critical: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }
}

public enum AlertCategory: String, CaseIterable, Identifiable {
    case trade, safety, risk, data, ops, model, research, review
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .trade: "交易"
        case .safety: "安全"
        case .risk: "风险"
        case .data: "数据"
        case .ops: "运维"
        case .model: "模型"
        case .research: "研究"
        case .review: "复盘"
        }
    }
    public var icon: String {
        switch self {
        case .trade: "arrow.left.arrow.right"
        case .safety: "lock.shield"
        case .risk: "gauge.with.dots.needle.67percent"
        case .data: "externaldrive.connected.to.line.below"
        case .ops: "wrench.and.screwdriver"
        case .model: "cpu"
        case .research: "flask"
        case .review: "doc.text.magnifyingglass"
        }
    }
}

public struct TerminalAlert: Identifiable, Hashable {
    public let id: String
    public let source: String
    public let category: AlertCategory
    public let severity: AlertSeverity
    public let title: String
    public let detail: String
    public let at: Date
}

// MARK: - Cloud, AI, remote

public struct CloudAlbum: Identifiable {
    public let name: String
    public let count: Int
    public let symbol: String
    public let updated: Date
    public var id: String { name }
}

public struct CloudLibrary {
    public let photos: Int
    public let videos: Int
    public let librarySizeGB: Double
    public let lastUpload: Date
    public let pendingUploads: Int
    public let albums: [CloudAlbum]
}

public struct StorageVolume: Identifiable {
    public let key: String
    public let title: String
    public let role: String
    public let usedGB: Double
    public let totalGB: Double
    public let mounted: Bool
    public var id: String { key }
    public var usedFraction: Double { totalGB > 0 ? usedGB / totalGB : 0 }
    public var freeGB: Double { max(0, totalGB - usedGB) }
}

public struct AIService: Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let icon: String
    public let state: TerminalState
}

public struct AISuggestion: Identifiable {
    public let id: String
    public let title: String
    public let reason: String
    public let category: AlertCategory
}

public struct AIReview {
    public let date: Date
    public let headline: String
    public let points: [String]
}

public struct RemoteEntry: Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let icon: String
    public let address: String
    public let isPrimary: Bool
}

extension StorageVolume {
    /// Plan §3.2 labels: internal = 内置盘, main = 三星 T7（主盘）, backup = 备份, photos = 照片.
    public static let layout: [(key: String, title: String, role: String)] = [
        ("internal", "内置盘", "系统与代码"),
        ("main", "三星 T7", "主盘 · 数据与模型"),
        ("backup", "备份", "Time Machine"),
        ("photos", "照片", "Immich 照片库"),
    ]

    public static func volumes(from host: HostStatus?) -> [StorageVolume] {
        layout.map { item in
            let disk = host?.disks?[item.key] ?? nil
            let total = disk?.total_gb ?? 0
            let mounted = (disk?.mounted ?? false) && total > 0
            return StorageVolume(key: item.key, title: item.title, role: item.role,
                                 usedGB: mounted ? total - (disk?.free_gb ?? 0) : 0, totalGB: total, mounted: mounted)
        }
    }
}

// MARK: - Fixtures

public enum DemoTerminalData {
    /// Dates are relative to launch so the "minutes ago" labels stay readable.
    private static let launch = Date()
    private static func ago(minutes: Double) -> Date { launch.addingTimeInterval(-minutes * 60) }
    private static func ahead(minutes: Double) -> Date { launch.addingTimeInterval(minutes * 60) }

    private static func series(days: Int, drift: Double, wobble: Double, benchDrift: Double, seed: Double) -> [TradingReportPoint] {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: launch)
        var equity = 1.0, bench = 1.0
        return (0..<days).map { day in
            let t = Double(day) + seed
            equity *= 1 + drift + wobble * sin(t * 1.7) * cos(t * 0.6)
            bench *= 1 + benchDrift + wobble * 0.7 * sin(t * 1.1 + 0.4)
            let date = calendar.date(byAdding: .day, value: day - days + 1, to: start) ?? start
            return TradingReportPoint(date: date, equity: equity, benchmark: bench)
        }
    }

    private static func report(_ type: String, _ summary: String, days: Int, drift: Double, wobble: Double,
                               bench: Double, seed: Double, turnover: Double, cost: Double) -> TradingReport {
        let points = series(days: days, drift: drift, wobble: wobble, benchDrift: bench, seed: seed)
        // The series' implicit base is 1.0 (the window's start NAV), so the peak starts there: a loss on the
        // first day counts. This matches the backtest windows in the Mac's report-versus-backtest comparison.
        var peak = 1.0, drawdown = 0.0
        for p in points { peak = max(peak, p.equity); drawdown = max(drawdown, (peak - p.equity) / peak) }
        return TradingReport(type: type, summary: summary,
                             returnPct: (points.last?.equity ?? 1) - 1,
                             benchmarkPct: (points.last?.benchmark ?? 1) - 1,
                             maxDrawdown: drawdown, turnover: turnover, costBps: cost, points: points)
    }

    public static let lines: [TradingLine] = [
        TradingLine(
            id: "crypto", title: "加密 v2", caption: "CRYPTO · ORDER FLOW", icon: "bitcoinsign.circle",
            mode: .shadow, state: .ok, lastRun: ago(minutes: 4), lastResult: "封存完成 · 无异常",
            nextRun: ahead(minutes: 11), scale: 0.0, checksPassed: 7, checksTotal: 12,
            stages: [
                TradingStage(name: "采集", state: .ok, note: "清算、大单、延迟 3 路正常"),
                TradingStage(name: "特征", state: .ok, note: "15 分钟窗口已更新"),
                TradingStage(name: "信号", state: .ok, note: "LightGBM + NN3 集成"),
                TradingStage(name: "风控", state: .warning, note: "扩容开关 STOP_CRYPTO_EXPAND 生效"),
                TradingStage(name: "执行", state: .idle, note: "影子阶段，不下单"),
            ],
            sleeves: [
                TradingSleeve(name: "订单流", mode: .shadow, weight: 0.45, returnPct: 0.031),
                TradingSleeve(name: "资金费率", mode: .shadow, weight: 0.30, returnPct: 0.012),
                TradingSleeve(name: "清算反转", mode: .shadow, weight: 0.25, returnPct: -0.006),
            ],
            daily: report("daily", "订单流信号稳定，资金费率腿贡献平缓。", days: 2, drift: 0.002, wobble: 0.004, bench: 0.001, seed: 1, turnover: 0.18, cost: 3.1),
            weekly: report("weekly", "影子收益跑赢 BTC 基准，回撤在阈值内。", days: 30, drift: 0.0012, wobble: 0.009, bench: 0.0006, seed: 1, turnover: 1.9, cost: 3.4)
        ),
        TradingLine(
            id: "stock", title: "股票模拟盘", caption: "STOCK · PAPER · 名义 $1M", icon: "chart.line.uptrend.xyaxis",
            mode: .paper, state: .ok, lastRun: ago(minutes: 600), lastResult: "收盘调仓完成 · 8 笔成交",
            nextRun: ahead(minutes: 840), scale: 1.0, checksPassed: 10, checksTotal: 12,
            stages: [
                TradingStage(name: "数据", state: .ok, note: "日线与因子已就绪"),
                TradingStage(name: "选股", state: .ok, note: "Meta 模型 18c"),
                TradingStage(name: "组合", state: .ok, note: "ETF 核心 + 选股卫星"),
                TradingStage(name: "成交", state: .ok, note: "模拟账户，8 笔"),
            ],
            sleeves: [
                TradingSleeve(name: "核心 ETF", mode: .paper, weight: 0.6, returnPct: 0.024),
                TradingSleeve(name: "量化选股", mode: .paper, weight: 0.4, returnPct: 0.047),
            ],
            daily: report("daily", "科技权重上调，换手低于预算。", days: 2, drift: 0.003, wobble: 0.005, bench: 0.002, seed: 4, turnover: 0.06, cost: 1.2),
            weekly: report("weekly", "跑赢 SPY 1.4 个百分点，主要来自选股腿。", days: 30, drift: 0.0011, wobble: 0.007, bench: 0.0007, seed: 4, turnover: 0.42, cost: 1.4)
        ),
        TradingLine(
            id: "account_risk", title: "账户风控", caption: "ACCOUNT RISK · ALL LINES", icon: "shield.lefthalf.filled",
            mode: .paper, state: .ok, lastRun: ago(minutes: 30), lastResult: "全部线路在限额内",
            nextRun: ahead(minutes: 30), scale: 1.0, checksPassed: 5, checksTotal: 6,
            stages: [
                TradingStage(name: "敞口", state: .ok, note: "合并敞口 62%"),
                TradingStage(name: "回撤", state: .ok, note: "距限额 4.8%"),
                TradingStage(name: "缩放", state: .ok, note: "股票 1.0 · 加密 0.0"),
            ],
            sleeves: [],
            daily: report("daily", "无缩放调整。", days: 2, drift: 0.001, wobble: 0.002, bench: 0.001, seed: 7, turnover: 0, cost: 0),
            weekly: report("weekly", "风险预算使用 58%。", days: 30, drift: 0.0006, wobble: 0.004, bench: 0.0005, seed: 7, turnover: 0, cost: 0)
        ),
    ]

    public static let alerts: [TerminalAlert] = [
        TerminalAlert(id: "host:forward15m:stale", source: "host-status", category: .data, severity: .warning,
                      title: "forward15m 采集超时", detail: "最后心跳 70 分钟前，告警阈值 45 分钟。", at: ago(minutes: 25)),
        TerminalAlert(id: "relay:crypto:stop", source: "crypto", category: .safety, severity: .critical,
                      title: "加密扩容已暂停", detail: "研究队列放置了 STOP_CRYPTO_EXPAND，扩容任务不会启动。", at: ago(minutes: 52)),
        TerminalAlert(id: "relay:risk:exposure", source: "account_risk", category: .risk, severity: .warning,
                      title: "NVDA 合并敞口偏高", detail: "个人与量化合并持有 50 股，占组合 18%。", at: ago(minutes: 95)),
        TerminalAlert(id: "relay:stock:fills", source: "stock", category: .trade, severity: .info,
                      title: "股票模拟盘调仓完成", detail: "收盘后 8 笔模拟成交，换手 6%。", at: ago(minutes: 610)),
        TerminalAlert(id: "relay:model:shadow", source: "crypto", category: .model, severity: .info,
                      title: "NN3 影子挑战者第 12 天", detail: "挑战者只比较结果，不会自动替换冠军。", at: ago(minutes: 720)),
        TerminalAlert(id: "host:disk:photos", source: "host-status", category: .ops, severity: .warning,
                      title: "照片盘未挂载", detail: "/Volumes/照片 没有挂载，Immich 上传会暂存到内置盘。", at: ago(minutes: 840)),
        TerminalAlert(id: "relay:review:daily", source: "review", category: .review, severity: .info,
                      title: "每日复盘已生成", detail: "收益、基准、回撤与成本的复盘已可查看。", at: ago(minutes: 1_020)),
        TerminalAlert(id: "relay:research:queue", source: "research", category: .research, severity: .info,
                      title: "回测队列完成 3 项", detail: "19b 订单流集成、18c 元模型与期权研究。", at: ago(minutes: 1_380)),
    ]

    /// The four volumes of the sample GET /host document (photos and backup are unmounted there).
    public static var volumes: [StorageVolume] { StorageVolume.volumes(from: ServerSample.host) }

    public static let cloud = CloudLibrary(
        photos: 18_426, videos: 912, librarySizeGB: 648.2, lastUpload: ago(minutes: 180), pendingUploads: 0,
        albums: [
            CloudAlbum(name: "最近项目", count: 214, symbol: "clock", updated: ago(minutes: 180)),
            CloudAlbum(name: "旅行", count: 3_208, symbol: "airplane", updated: ago(minutes: 4_300)),
            CloudAlbum(name: "家人", count: 5_611, symbol: "heart", updated: ago(minutes: 2_900)),
            CloudAlbum(name: "截图", count: 1_942, symbol: "camera.viewfinder", updated: ago(minutes: 600)),
            CloudAlbum(name: "文档扫描", count: 386, symbol: "doc.viewfinder", updated: ago(minutes: 9_800)),
            CloudAlbum(name: "视频", count: 912, symbol: "video", updated: ago(minutes: 7_200)),
        ]
    )

    public static let aiServices: [AIService] = [
        AIService(id: "qa", title: "资料问答", detail: "就自己的笔记、研报和代码提问", icon: "text.book.closed", state: .pending),
        AIService(id: "duty", title: "值班员建议", detail: "读告警和心跳，给出下一步检查", icon: "person.badge.shield.checkmark", state: .pending),
        AIService(id: "review", title: "每日复盘", detail: "每晚汇总交易线路和服务器", icon: "doc.text.magnifyingglass", state: .pending),
    ]

    public static let aiSuggestions: [AISuggestion] = [
        AISuggestion(id: "s1", title: "检查 forward15m 采集任务", reason: "心跳已超时 70 分钟，其他采集器正常，可能是单个任务卡住。", category: .data),
        AISuggestion(id: "s2", title: "挂载照片盘", reason: "照片盘未挂载时上传会落到内置盘，内置盘剩余 612 GB。", category: .ops),
        AISuggestion(id: "s3", title: "确认扩容暂停是否仍需要", reason: "STOP_CRYPTO_EXPAND 已存在 2 天。", category: .safety),
    ]

    public static let review = AIReview(
        date: ago(minutes: 1_020),
        headline: "两条线路平稳，服务器有一项采集超时。",
        points: [
            "股票模拟盘收盘调仓 8 笔，跑赢 SPY 0.3 个百分点。",
            "加密 v2 仍在影子阶段，上线检验通过 7/12。",
            "forward15m 采集超时，其他 6 个采集器心跳正常。",
            "照片盘未挂载，今日上传暂存内置盘。",
        ]
    )

    public static let remoteEntries: [RemoteEntry] = [
        RemoteEntry(id: "jump", title: "Jump Desktop", detail: "Fluid 协议，经 Tailscale 直连，画面最流畅",
                    icon: "macwindow.on.rectangle", address: TerminalPlaceholders.host, isPrimary: true),
        RemoteEntry(id: "vnc", title: "屏幕共享", detail: "系统自带，备用方式",
                    icon: "rectangle.on.rectangle", address: TerminalPlaceholders.screenSharing, isPrimary: false),
        RemoteEntry(id: "immich", title: "Immich", detail: "照片上传与浏览",
                    icon: "photo.on.rectangle.angled", address: TerminalPlaceholders.immich, isPrimary: false),
        RemoteEntry(id: "console", title: "AI 控制台", detail: "浏览器打开，自己登录",
                    icon: "terminal", address: TerminalPlaceholders.aiConsole, isPrimary: false),
    ]
}

// MARK: - Shared state for the alert pages

/// Read state and filters for the alert list: the relay's /alerts once a relay is paired (ServerStore.events), the
/// built-in alerts before. Read state stays on this device across launches.
@MainActor
public final class TerminalDemo: ObservableObject {
    @Published public var alerts: [TerminalAlert] = DemoTerminalData.alerts
    @Published public var read: Set<String> = StoredIDs.load(StoredIDs.alertsReadKey) {
        didSet { StoredIDs.save(read, StoredIDs.alertsReadKey) }
    }
    @Published public var severity: AlertSeverity?
    @Published public var category: AlertCategory?

    private var subscription: AnyCancellable?

    public init(followsRelay: Bool = true) {
        guard followsRelay else { return }
        let server = ServerStore.shared
        subscription = server.$events.combineLatest(server.$isSample, server.$pairingState)
            .map { events, sample, pairing in
                pairing != .unpaired && !sample ? events.map { $0.asTerminalAlert() } : DemoTerminalData.alerts
            }
            .sink { [weak self] alerts in self?.alerts = alerts }
    }

    public var unreadCount: Int { alerts.filter { !read.contains($0.id) }.count }

    public var filtered: [TerminalAlert] {
        alerts.filter { (severity == nil || $0.severity == severity) && (category == nil || $0.category == category) }
    }

    public func count(_ severity: AlertSeverity) -> Int { alerts.filter { $0.severity == severity }.count }

    public func markAllRead() { read.formUnion(alerts.map(\.id)) }

    public func toggleRead(_ alert: TerminalAlert) {
        if read.contains(alert.id) { read.remove(alert.id) } else { read.insert(alert.id) }
    }
}

public enum TerminalFormat {
    public static func relative(_ date: Date, now: Date = .now) -> String {
        ServerDates.age(minutes: max(0, now.timeIntervalSince(date) / 60))
    }

    public static func percent(_ fraction: Double, signed: Bool = true) -> String {
        String(format: signed ? "%+.2f%%" : "%.1f%%", fraction * 100)
    }

    public static func gigabytes(_ value: Double) -> String {
        value >= 1_000 ? String(format: "%.2f TB", value / 1_000) : String(format: "%.0f GB", value)
    }
}
