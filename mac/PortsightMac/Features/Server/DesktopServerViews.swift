import SwiftUI
import Charts
import PortSightKit

/// 服务器 · 概况: state, load / memory / temperature / power, recent history and the four volumes.
struct DesktopServerOverview: View {
    @ObservedObject private var store = ServerStore.shared

    var body: some View {
        if let host = store.host, host.hasData {
            DesktopFullPage {
                DesktopServerBanner(store: store)
                header(host)
                vitals(host)
                if !store.feeds.isEmpty {
                    DesktopPageSection(title: "量化数据", subtitle: "字段确定后再做页面") {
                        HStack(alignment: .top, spacing: 28) {
                            ForEach(RelayEndpoint.pending, id: \.self) { endpoint in
                                if let state = store.feeds[endpoint] {
                                    DesktopStat(label: endpoint.title, value: state.title, detail: Self.feedDetail(state))
                                }
                            }
                        }
                    }
                }
                DesktopPageSection(title: "最近负载与内存", subtitle: "每 5 分钟一点 · 服务器只保留 24 小时") {
                    DesktopHostHistoryChart(points: host.history ?? [])
                }
                DesktopPageSection(title: "磁盘", subtitle: "内置盘、三星 T7、备份与照片") {
                    Grid(horizontalSpacing: 36, verticalSpacing: 26) {
                        let volumes = StorageVolume.volumes(from: host)
                        GridRow { DesktopVolumeRow(volume: volumes[0]); DesktopVolumeRow(volume: volumes[1]) }
                        GridRow { DesktopVolumeRow(volume: volumes[2]); DesktopVolumeRow(volume: volumes[3]) }
                    }
                }
                if let active = host.alerts_active, !active.isEmpty {
                    DesktopPageSection(title: "活跃告警") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(active) { alert in
                                HStack(spacing: 10) {
                                    DesktopStatusDot(color: DesktopStatus.color(relay: alert.severity))
                                    Text(alert.title ?? alert.key).font(.system(size: 13))
                                    Spacer()
                                    Text("始于 " + ServerDates.clock(ServerDates.parse(alert.since))).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        } else {
            DesktopServerNoData(store: store)
        }
    }

    private func header(_ host: HostStatus) -> some View {
        let summary = host.summary
        return DesktopPageHeader(
            eyebrow: (host.host?.hostname ?? "Mac mini") + " · 已运行 " + hours(host.host?.uptime_hours),
            title: summary?.state == "ok" ? "运行正常" : summary?.state == "critical" ? "出现严重问题" : "需要留意",
            detail: "心跳正常 \(summary?.heartbeats_ok ?? 0) · 异常 \(summary?.heartbeats_problem ?? 0) · 活跃告警 \(summary?.active_alerts ?? 0)"
        ) {
            VStack(alignment: .trailing, spacing: 10) {
                DesktopConnectionBadge()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("数据时间").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(ServerDates.clock(ServerDates.parse(host.as_of))).font(.system(size: 13, weight: .medium)).monospacedDigit()
                }
            }
        }
    }

    private func vitals(_ host: HostStatus) -> some View {
        let machine = host.host
        let thermal = machine?.thermal
        return VStack(alignment: .leading, spacing: 18) {
            if thermal?.overheated == true {
                HStack(spacing: 12) {
                    Image(systemName: "thermometer.high").foregroundStyle(.red)
                    Text("Mac mini 过热").font(.system(size: 13, weight: .semibold))
                    Text("系统已经降频，留意散热和负载。").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Color.red.opacity(0.08), in: Capsule())
            }
            HStack(alignment: .top, spacing: 28) {
                DesktopStat(label: "负载 1 / 5 / 15 分钟",
                            value: [machine?.load?.m1, machine?.load?.m5, machine?.load?.m15].map { fmt($0) }.joined(separator: " / "),
                            detail: "\(machine?.cpu_count ?? 0) 核 · 每核 " + fmt(machine?.load?.per_core_5m, digits: 2))
                DesktopStat(label: "内存压力", value: pressure(machine?.memory?.pressure),
                            detail: "空闲 " + fmt(machine?.memory?.free_pct) + "% · 共 " + fmt(machine?.memory?.total_gb) + " GB")
                DesktopStat(label: "CPU / GPU 温度", value: DesktopStatus.temperatures(thermal),
                            detail: DesktopStatus.thermalNote(thermal))
                DesktopStat(label: "电源", value: powerTitle(machine?.power), detail: powerNote(machine?.power))
            }
        }
    }

    private func powerTitle(_ power: HostPower?) -> String {
        switch power?.kind {
        case "ac": "市电"
        case "battery": "电池"
        case "ups": "UPS"
        default: "—"
        }
    }

    private func powerNote(_ power: HostPower?) -> String {
        if let percent = power?.percent { return "电量 \(percent)%" }
        switch power?.kind {
        case "ac": return "接通电源"
        case "ups", "battery": return "电量未知"
        default: return "—"
        }
    }

    private static func feedDetail(_ state: RelayFeedState) -> String {
        switch state {
        case .noData: "量化系统还没写入"
        case .received(let asOf): asOf.map { "数据时间 " + ServerDates.clock(ServerDates.parse($0)) } ?? "—"
        case .needsRepair: "到设置 → 量化服务器 重新配对"
        case .failed(let reason): reason
        }
    }

    private func fmt(_ value: Double?, digits: Int = 1) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0...digits))) } ?? "—"
    }

    private func hours(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value >= 48 ? fmt(value / 24) + " 天" : fmt(value) + " 小时"
    }

    private func pressure(_ value: String?) -> String {
        switch value {
        case "normal": "正常"
        case "warn", "warning": "偏高"
        case "critical": "紧张"
        default: "—"
        }
    }
}

/// Stale / sample / offline banner, matching the iOS server page rules.
struct DesktopServerBanner: View {
    @ObservedObject var store: ServerStore
    var now = Date()

    var body: some View {
        if store.pairingState == .needsRepair {
            banner(color: DesktopTheme.orange, icon: "exclamationmark.triangle.fill", title: "需要重新配对",
                   detail: "服务器不再认这台 Mac 的凭证，到设置 → 量化服务器 重新输入配对码。")
        } else if store.isSample {
            banner(color: DesktopTheme.blue, icon: "eye", title: "尚未配对", detail: "在设置 → 量化服务器 里配对后显示实时状态。")
        } else if !store.isPaired {
            banner(color: .secondary, icon: "link", title: "尚未配对", detail: "在设置 → 量化服务器 里填地址和配对码。")
        } else if let problem = store.connectionBanner(now: now, networkHint: "网络") {
            banner(color: problem.kind == .stale ? .red : DesktopTheme.orange,
                   icon: problem.kind == .offline ? "wifi.exclamationmark"
                       : problem.kind == .rateLimited ? "hourglass" : "exclamationmark.triangle.fill",
                   title: problem.title, detail: problem.detail)
        }
    }

    private func banner(color: Color, icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(color)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(color.opacity(0.08), in: Capsule())
    }
}

/// 服务器 pages with nothing to show: not paired yet (no data saved), or the relay has no host status yet.
struct DesktopServerNoData: View {
    @ObservedObject var store: ServerStore

    var body: some View {
        VStack(spacing: 16) {
            DesktopServerBanner(store: store)
            if let host = store.host, !host.hasData {
                ContentUnavailableView("暂无数据", systemImage: "macmini",
                                       description: Text(host.message ?? "Mac mini 上的主机状态任务还没写入数据。"))
            } else if store.pairingState != .unpaired {
                ContentUnavailableView("暂无数据", systemImage: "macmini", description: Text("连上服务器后显示实时状态。"))
            } else {
                ContentUnavailableView("尚未接入", systemImage: "macmini", description: Text("Mac mini 到位并配对后显示实时状态。"))
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DesktopHostHistoryChart: View {
    let points: [HostHistoryPoint]

    private struct Sample: Identifiable {
        let date: Date
        let value: Double
        let series: String
        var id: String { series + date.description }
    }

    private var samples: [Sample] {
        points.flatMap { point -> [Sample] in
            guard let date = ServerDates.parse(point.at) else { return [] }
            var out: [Sample] = []
            if let load = point.load5 { out.append(Sample(date: date, value: load, series: "负载")) }
            if let free = point.memFreePct { out.append(Sample(date: date, value: free / 10, series: "内存空闲")) }
            return out
        }
    }

    var body: some View {
        if samples.isEmpty {
            DesktopPendingLabel(text: "暂无历史")
        } else {
            Chart(samples) { sample in
                LineMark(x: .value("时间", sample.date), y: .value("数值", sample.value), series: .value("项目", sample.series))
                    .foregroundStyle(by: .value("项目", sample.series))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartForegroundStyleScale(["负载": DesktopTheme.blue, "内存空闲": DesktopTheme.green])
            .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(.separator); AxisValueLabel() } }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { AxisValueLabel(format: .dateTime.hour().minute()) } }
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 200)
            Text("内存空闲按 ÷10 显示，与负载同一坐标。").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
}

/// 服务器 · 心跳: every runner, sleeve and collector in a sortable native table.
struct DesktopHeartbeatsView: View {
    @ObservedObject private var store = ServerStore.shared
    @State private var order = [KeyPathComparator(\Row.rank), KeyPathComparator(\Row.name)]
    @State private var kind = "全部"

    struct Row: Identifiable {
        let beat: HostHeartbeat
        var id: String { beat.name }
        var name: String { beat.name }
        var kind: String { beat.kind ?? "—" }
        var age: Double { beat.age_min ?? .infinity }
        var state: String { beat.state ?? "—" }
        /// Problems first.
        var rank: Int {
            switch beat.state {
            case "critical", "missing": 0
            case "stale", "error": 1
            case "ok": 2
            default: 3
            }
        }
    }

    private var rows: [Row] {
        (store.host?.heartbeats ?? []).map(Row.init).filter { kind == "全部" || $0.kind == kind }.sorted(using: order)
    }

    var body: some View {
        if let host = store.host, host.hasData {
            beats
        } else {
            DesktopServerNoData(store: store)
        }
    }

    private var beats: some View {
        VStack(alignment: .leading, spacing: 0) {
            DesktopServerBanner(store: store)
                .padding(.horizontal, 28).padding(.top, 20)
            let all = store.host?.heartbeats ?? []
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(all.isEmpty ? "暂无心跳" : "\(all.filter { $0.state == "ok" }.count) / \(all.count) 正常")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("runner 跑策略，sleeve 是子策略，collector 采集数据").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                DesktopCapsulePicker(title: "类型", options: ["全部", "runner", "sleeve", "collector"], selection: $kind) { $0 }.labelsHidden().fixedSize()
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
            if all.isEmpty || rows.isEmpty {
                DesktopPendingLabel(text: all.isEmpty ? "暂无" : "没有这类心跳")
                    .padding(.horizontal, 28)
                Spacer(minLength: 0)
            } else {
            Table(rows, sortOrder: $order) {
                TableColumn("状态", value: \.rank) { row in
                    HStack(spacing: 7) {
                        DesktopStatusDot(color: DesktopStatus.color(relay: row.beat.state))
                        Text(DesktopStatus.title(relay: row.beat.state))
                    }
                }
                .width(min: 90, ideal: 110)
                TableColumn("名称", value: \.name) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name).font(.system(size: 12, weight: .medium))
                        if let label = row.beat.label { Text(label).font(.system(size: 10)).foregroundStyle(.tertiary) }
                    }
                }
                .width(min: 200, ideal: 280)
                TableColumn("类型", value: \.kind) { Text($0.kind).foregroundStyle(.secondary) }
                    .width(min: 70, ideal: 90)
                TableColumn("最后心跳", value: \.age) { row in
                    Text(ServerDates.age(minutes: row.beat.age_min)).monospacedDigit()
                }
                .width(min: 90, ideal: 110)
                TableColumn("阈值") { row in
                    Text(threshold(row.beat)).foregroundStyle(.secondary).monospacedDigit()
                }
                .width(min: 100, ideal: 130)
            }
            .tableStyle(.inset)
            .scrollContentBackground(.hidden)
            }
        }
    }

    private func threshold(_ beat: HostHeartbeat) -> String {
        guard let warn = beat.warn_min, let crit = beat.crit_min else { return "—" }
        return "\(Int(warn)) / \(Int(crit)) 分钟"
    }
}

/// 服务器 · 任务与队列: launchd jobs, the heavy-job lock, stop files, deadman and collector health.
struct DesktopJobsView: View {
    @ObservedObject private var store = ServerStore.shared
    @State private var order = [KeyPathComparator(\Job.name)]

    struct Job: Identifiable {
        let name: String
        let job: HostJob
        var id: String { name }
        var state: String { job.state ?? "—" }
    }

    private var jobs: [Job] {
        (store.host?.launchd?.jobs ?? [:]).map { Job(name: $0.key, job: $0.value) }.sorted(using: order)
    }

    var body: some View {
        if let host = store.host, host.hasData {
            page
        } else {
            DesktopServerNoData(store: store)
        }
    }

    private var page: some View {
        DesktopFullPage {
            DesktopServerBanner(store: store)
            let queue = store.host?.queue
            DesktopPageHeader(eyebrow: "重任务队列",
                              title: queue?.heavy_lock?.owner.map { "\($0) 占用中" } ?? "空闲",
                              detail: queue?.heavy_lock.map { "PID \($0.pid ?? 0) · 已持有 " + ($0.held_hours.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—") + " 小时" + (($0.stale ?? false) ? " · 疑似卡住" : "") }
                                ?? "没有任务持有重任务锁")

            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("停止文件").font(.system(size: 11)).foregroundStyle(.secondary)
                    if let stops = queue?.stop_files, !stops.isEmpty {
                        ForEach(stops) { stop in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stop.name).font(.system(size: 12, weight: .medium, design: .monospaced))
                                    Text((stop.where ?? "") + " · " + ServerDates.clock(ServerDates.parse(stop.since))).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "hand.raised.fill").foregroundStyle(DesktopTheme.orange) }
                        }
                    } else {
                        Text("无").font(.system(size: 13))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                let deadman = store.host?.deadman
                DesktopStat(label: "Deadman 外部探测", value: (deadman?.enabled ?? false) ? "已开启" : "未开启",
                            detail: "上次成功 " + ServerDates.clock(ServerDates.parse(deadman?.last_ok)) + " · 连续失败 \(deadman?.consecutive_failures ?? 0)")
                let health = store.host?.collector_health
                let hasReport = health != nil && health?.available != false
                DesktopStat(label: "采集健康报告", value: hasReport ? "\(health?.alert_count ?? 0) 项提醒" : "暂无",
                            detail: hasReport ? (health?.alerts?.first ?? "全部正常") : "采集日报还没生成")
            }

            DesktopPageSection(title: "launchd 任务", subtitle: "只读：App 不会启动、停止或修改任务") {
              if store.host?.launchd?.available == false || jobs.isEmpty {
                DesktopPendingLabel(text: "暂无")
              } else {
                Table(jobs, sortOrder: $order) {
                    TableColumn("任务", value: \.name) { Text($0.name).font(.system(size: 12, design: .monospaced)) }
                        .width(min: 240, ideal: 320)
                    TableColumn("状态", value: \.state) { job in
                        HStack(spacing: 7) {
                            DesktopStatusDot(color: DesktopStatus.color(relay: job.job.state))
                            Text(DesktopStatus.title(relay: job.job.state))
                        }
                    }
                    .width(min: 80, ideal: 100)
                    TableColumn("PID") { Text($0.job.pid.map(String.init) ?? "—").monospacedDigit().foregroundStyle(.secondary) }
                        .width(min: 60, ideal: 70)
                    TableColumn("上次退出") { Text($0.job.last_exit ?? "—").monospacedDigit().foregroundStyle(.secondary) }
                        .width(min: 60, ideal: 80)
                    TableColumn("已加载") { job in
                        Image(systemName: (job.job.loaded ?? false) ? "checkmark" : "minus").foregroundStyle(.secondary)
                    }
                    .width(min: 50, ideal: 60)
                }
                .tableStyle(.inset)
                .scrollContentBackground(.hidden)
                .frame(height: CGFloat(max(jobs.count, 1)) * 30 + 34)
              }
            }
        }
    }
}
