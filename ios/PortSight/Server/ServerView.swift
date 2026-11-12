//
//  ServerView.swift
//  PortSight
//
//  The "服务器" tab: the Mac mini's load, memory, temperature, disks, collectors, launchd jobs, heavy-job queue and
//  recent alerts, read from the relay's GET /host. Read-only: nothing here can start, stop or change anything.
//

import SwiftUI
import Charts
import Combine
import PortSightKit

struct ServerView: View {
    @ObservedObject private var store = ServerStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showConnection = false
    @State private var now = Date()
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    banner
                    if let host = store.host, !host.hasData {
                        // The relay answered, but the Mac mini's host status job has not written anything yet.
                        ServerCard(title: "主机状态", icon: "server.rack") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("暂无数据").font(.title3.weight(.semibold))
                                Text(host.message ?? "Mac mini 上的主机状态任务还没写入数据。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if !store.feeds.isEmpty { ServerFeedsCard(feeds: store.feeds) }
                        ServerCloudLink()
                        ServerRemoteLink()
                    } else if let host = store.host {
                        ServerSummaryCard(host: host, fetchedAt: store.fetchedAt)
                        ServerLoadCard(host: host)
                        if !store.feeds.isEmpty { ServerFeedsCard(feeds: store.feeds) }
                        ServerDisksCard(disks: host.disks ?? [:])
                        ServerCloudLink()
                        ServerRemoteLink()
                        ServerHeartbeatsCard(beats: host.heartbeats ?? [])
                        ServerAlertsCard(active: host.alerts_active ?? [], recent: store.events.isEmpty ? (host.alerts_recent ?? []) : store.events)
                        ServerQueueCard(queue: host.queue, deadman: host.deadman, push: host.push, report: host.collector_health)
                        ServerJobsCard(jobs: host.launchd?.jobs ?? [:], available: host.launchd?.available != false)
                    } else if store.pairingState != .unpaired {
                        ContentUnavailableView("暂无数据", systemImage: "server.rack",
                                               description: Text("已配对，连上服务器后显示 Mac mini 的状态。"))
                            .padding(.top, 40)
                    } else {
                        ContentUnavailableView("还没有服务器数据", systemImage: "server.rack",
                                               description: Text("点上面的横幅配对，或到「更多 → 通用设置 → 量化服务器」填 Mac mini 的 HTTPS 地址和配对码。"))
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .portSightBackdrop()
            .toolbar {
                // 云盘 and 远程 live with the Mac mini they run on.
                ToolbarItemGroup(placement: .topBarLeading) {
                    NavigationLink { TerminalCloudView() } label: { Image(systemName: "photo.stack") }
                        .accessibilityLabel("云盘")
                    NavigationLink { TerminalRemoteView() } label: { Image(systemName: "rectangle.on.rectangle") }
                        .accessibilityLabel("远程桌面")
                }
                // No refresh button: pull to refresh, or tap 连接失败 to reconnect.
                if store.pairingState != .unpaired && !store.isSample {
                    ToolbarItem(placement: .topBarTrailing) {
                        ServerConnectionToolbarItem(showSettings: $showSettings, showDetails: $showConnection)
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                MessageCenterToolbar()
            }
            // In its own task: SwiftUI may cancel the pull-to-refresh task while the page updates, which would
            // cancel the request with it.
            .refreshable { await Task { await store.refresh(force: true) }.value }
            // Every 10 s while this tab is on screen and the app is in front; switching tabs or leaving the app
            // cancels it (no reads for a page nobody sees).
            .task(id: scenePhase == .active) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    await store.refresh()
                    try? await Task.sleep(for: .seconds(RelayAPI.minRefreshInterval))
                }
            }
            .onReceive(ticker) { now = $0 }
            .sheet(isPresented: $showSettings) { ServerSettingsView() }
            // Kept here, not on the toolbar item, so a refresh that fails while it is open does not close it.
            .sheet(isPresented: $showConnection) { ConnectionDetailView(status: store.connection) }
        }
    }

    @ViewBuilder private var banner: some View {
        if store.pairingState == .needsRepair {
            Button { showSettings = true } label: {
                ServerBanner(color: .orange, icon: "exclamationmark.triangle.fill", title: "需要重新配对",
                             detail: "服务器不再认这台手机的凭证，点这里重新输入配对码。")
            }
            .buttonStyle(.plain)
        } else if !store.isPaired {
            Button { showSettings = true } label: {
                ServerBanner(color: .gray, icon: "link", title: "还没连接服务器",
                             detail: store.isSample ? "下面是样例。点这里配对（HTTPS 加密连接）" : "点这里配对（HTTPS 加密连接）")
            }
            .buttonStyle(.plain)
        } else if let problem = store.connectionBanner(now: now, networkHint: "手机网络") {
            ServerBanner(color: problem.kind == .stale ? .red : .orange,
                         icon: problem.kind == .offline ? "wifi.exclamationmark"
                             : problem.kind == .rateLimited ? "hourglass" : "exclamationmark.triangle.fill",
                         title: problem.title, detail: problem.detail)
        }
    }
}

// MARK: building blocks

/// The 服务器 tab's connection status in the toolbar. While the relay answers: the route, tap for its details.
/// When it cannot be reached (offline, a server error): 连接失败, and a tap reconnects; it shows 连接中 until that
/// try is over and takes no second tap meanwhile. When the server answered but holds this device off (429, or 403
/// on /host), a tap could not send anything, so it shows when it retries by itself instead. 需要重新配对 opens pairing.
/// One button whatever the state, so a state change never tears down what it opened.
struct ServerConnectionToolbarItem: View {
    @ObservedObject private var store = ServerStore.shared
    @Binding var showSettings: Bool
    @Binding var showDetails: Bool
    @State private var reconnecting = false
    /// When /host was last refused (403), seen here: the Kit asks it again 10 minutes later.
    @State private var lockedAt: Date?
    /// Redraws once the wait is over.
    @State private var tick = Date()

    private enum Mode: Equatable { case repair, connected, failed, reconnecting, waiting(Date?) }

    private func mode(at now: Date) -> Mode {
        if store.pairingState == .needsRepair { return .repair }
        guard store.lastFailure != nil, let failure = store.failure, failure != .unauthorized else { return .connected }
        if reconnecting || store.busy { return .reconnecting }
        switch failure {
        case .rateLimited:
            // The Kit sends nothing before blockedUntil; after it a tap gets through again.
            if let until = store.blockedUntil, until > now { return .waiting(until) }
            return .failed
        case .locked:
            // Refused until the 403 block ends (not public); the automatic refresh picks it up after that.
            let until = lockedAt.map { $0.addingTimeInterval(RelayAPI.lockoutWait) }
            return .waiting(until.flatMap { $0 > now ? $0 : nil })
        default:
            return .failed
        }
    }

    var body: some View {
        // `tick` is read here so the wait's end redraws the item.
        let current = mode(at: max(tick, .now))
        let retryAt: Date? = if case .waiting(let until) = current { until } else { nil }
        Button { tap(current) } label: { label(current) }
            .disabled(!(current == .repair || current == .connected || current == .failed))
            .accessibilityLabel(accessibility(current))
            .accessibilityHint(hint(current))
            .onChange(of: store.failure) { old, new in
                if new == .locked && old != .locked { lockedAt = store.lastFailure ?? .now }
                if new != .locked { lockedAt = nil }
            }
            .task(id: retryAt) {
                guard let retryAt else { return }
                let wait = retryAt.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(for: .seconds(wait + 1)) }
                if !Task.isCancelled { tick = .now }
            }
    }

    @ViewBuilder private func label(_ mode: Mode) -> some View {
        switch mode {
        case .repair:
            status("重新配对", color: .orange)
        case .connected:
            let route = store.connection
            HStack(spacing: 6) {
                Circle().fill(route.path.tint).frame(width: 8, height: 8)
                Text(route.latencyMs.map { "\($0) ms" } ?? route.path.title)
                    .font(.subheadline.weight(.medium)).monospacedDigit()
                    // The number rolls to its new value.
                    .contentTransition(.numericText(value: Double(route.latencyMs ?? 0)))
                    .animation(.smooth, value: route.latencyMs)
            }
            .padding(.horizontal, 4)
        case .failed:
            status("连接失败", color: .red)
        case .reconnecting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("连接中").font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 4)
        case .waiting(let until):
            status(until.map { ServerDates.clock($0) + " 后重试" } ?? "稍后重试", color: .orange)
        }
    }

    private func status(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(color).monospacedDigit()
        }
        .padding(.horizontal, 4)
    }

    private func tap(_ mode: Mode) {
        switch mode {
        case .repair: showSettings = true
        case .connected: showDetails = true
        case .failed: reconnect()
        case .reconnecting, .waiting: break
        }
    }

    private func accessibility(_ mode: Mode) -> String {
        switch mode {
        case .repair: "服务器需要重新配对"
        case .connected: "服务器连接：" + store.connection.path.title
        case .failed: "服务器连接失败"
        case .reconnecting: "正在重新连接服务器"
        case .waiting(let until):
            store.failure == .locked
                ? "服务器拒绝了这台设备的请求，" + (until.map { ServerDates.clock($0) + " 后" } ?? "稍后") + "自动重试"
                : "服务器让这台设备暂停请求，" + (until.map { ServerDates.clock($0) + " 后" } ?? "稍后") + "自动重试"
        }
    }

    private func hint(_ mode: Mode) -> String {
        switch mode {
        case .repair: "打开配对设置"
        case .connected: "查看连接详情"
        case .failed: "重新连接"
        case .reconnecting, .waiting: ""
        }
    }

    private func reconnect() {
        guard !reconnecting, !store.busy else { return }
        reconnecting = true
        Task {
            await store.refresh(force: true)
            reconnecting = false
        }
    }
}

/// 远程: Jump Desktop first, Screen Sharing as the fallback.
struct ServerRemoteLink: View {
    var body: some View {
        NavigationLink { TerminalRemoteView() } label: {
            ServerCard(title: "远程桌面", icon: "rectangle.on.rectangle") {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Jump Desktop").font(.title3.weight(.semibold))
                        Text("经 Tailscale 直连 · 屏幕共享备用").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// 云盘 lives with the disks it is stored on: Immich photos, storage and file transfer.
struct ServerCloudLink: View {
    private let library = DemoTerminalData.cloud

    var body: some View {
        NavigationLink { TerminalCloudView() } label: {
            ServerCard(title: "云盘", icon: "photo.stack") {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(library.photos.formatted() + " 张照片").font(.title3.weight(.semibold)).monospacedDigit()
                        Text(library.videos.formatted() + " 段视频 · " + TerminalFormat.gigabytes(library.librarySizeGB) + " · Immich")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct ServerCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) { Image(systemName: icon).foregroundStyle(.secondary); Text(title).font(.headline); Spacer() }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .portSightCard(cornerRadius: 30)
    }
}

struct ServerBanner: View {
    let color: Color
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ServerStateDot: View {
    let state: String?
    var body: some View {
        Circle().fill(ServerText.color(state)).frame(width: 8, height: 8)
    }
}

enum ServerText {
    /// CPU / GPU temperature colours: normal as plain text, 85–95 °C yellow, over 95 °C red.
    static func temperatureColor(_ level: TemperatureLevel?) -> Color {
        switch level {
        case .warm: warmYellow
        case .hot: .red
        case .normal, nil: .primary
        }
    }

    /// System yellow in dark mode; a deeper yellow in light mode so the figure stays readable on a light card.
    static let warmYellow = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemYellow : UIColor(red: 0.64, green: 0.46, blue: 0, alpha: 1)
    })

    static func color(_ state: String?) -> Color {
        switch state {
        case "ok", "running", "fresh": return .green
        case "stale", "warning", "error", "failed": return .orange
        case "critical", "missing", "down": return .red
        default: return .gray
        }
    }

    static func state(_ state: String?) -> String {
        switch state {
        case "ok": return "正常"
        case "stale": return "超时"
        case "critical": return "严重超时"
        case "missing": return "没有心跳"
        case "not_installed": return "未安装"
        case "stopped": return "已停止"
        case "error": return "出错"
        case "running": return "运行中"
        case "idle": return "待机"
        case "not_loaded": return "未加载"
        case "down": return "已停"
        case "failed": return "上次失败"
        default: return state ?? "—"
        }
    }

    static func summary(_ state: String?) -> String {
        switch state {
        case "ok": return "正常"
        case "warning": return "有警告"
        case "critical": return "有严重告警"
        default: return "未知"
        }
    }

    static let names: [String: String] = [
        "crypto_paper": "加密运行程序", "stock_daily": "股票运行程序", "account_risk": "账户层风控",
        "liquidations": "强平记录", "hl_big_trades": "HL 大单", "upbit_latency": "Upbit 上币延迟",
        "forward15m": "15 分钟采集", "okxgaps": "每小时采集", "snapshots": "6 小时快照",
        "hyperliquid_positions": "HL 持仓（每日）", "hyperliquid_fills": "HL 成交（每日）", "smart_money": "聪明钱（每日）",
    ]

    static func name(_ raw: String) -> String {
        if raw.hasPrefix("sleeve:") { return "子策略 " + raw.dropFirst("sleeve:".count) }
        return names[raw] ?? raw
    }

    static func number(_ value: Double?, _ digits: Int = 1) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(digits)f", value)
    }
}

// MARK: cards

/// /status, /account, /reports/latest and /advice. Until the quant system fills them and their fields are settled,
/// only whether there is data: `available: false` reads 暂无数据.
struct ServerFeedsCard: View {
    let feeds: [RelayEndpoint: RelayFeedState]

    var body: some View {
        ServerCard(title: "量化数据", icon: "tray.full") {
            ForEach(RelayEndpoint.pending, id: \.self) { endpoint in
                if let state = feeds[endpoint] {
                    HStack {
                        Text(endpoint.title).font(.subheadline)
                        Spacer()
                        Text(Self.detail(state)).font(.caption).foregroundStyle(Self.color(state))
                    }
                }
            }
        }
    }

    static func detail(_ state: RelayFeedState) -> String {
        switch state {
        case .received(let asOf): state.title + (asOf.map { " · " + ServerDates.clock(ServerDates.parse($0)) } ?? "")
        case .failed(let reason): state.title + "（\(reason)）"
        default: state.title
        }
    }

    static func color(_ state: RelayFeedState) -> Color {
        switch state {
        case .noData: .secondary
        case .received: .green
        case .needsRepair, .failed: .orange
        }
    }
}

struct ServerSummaryCard: View {
    let host: HostStatus
    let fetchedAt: Date?
    var body: some View {
        ServerCard(title: host.host?.hostname ?? "Mac mini", icon: "server.rack") {
            HStack(spacing: 8) {
                ServerStateDot(state: host.summary?.state)
                Text(ServerText.summary(host.summary?.state)).font(.title3.bold())
                Spacer()
                Text("\(host.summary?.active_alerts ?? 0) 条告警").font(.subheadline).foregroundStyle(.secondary)
            }
            // Two figures a row keeps the card short; one grid keeps every label and value in line. Footnote: at
            // subheadline the four columns are wider than the card on a 6.1" iPhone.
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    label("心跳")
                    value("\(host.summary?.heartbeats_ok ?? 0) 正常 · \(host.summary?.heartbeats_problem ?? 0) 有问题")
                    label("已运行").padding(.leading, 12)
                    value(host.host?.uptime_hours.map { String(format: "%.0f 小时", $0) } ?? "—")
                }
                GridRow {
                    label("数据时间")
                    value(ServerDates.clock(ServerDates.parse(host.as_of)))
                    label("手机同步").padding(.leading, 12)
                    value(ServerDates.clock(fetchedAt))
                }
            }
            .font(.footnote)
        }
    }

    private func label(_ title: String) -> some View {
        Text(title).foregroundStyle(.secondary).fixedSize()
    }

    private func value(_ text: String) -> some View {
        Text(text).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var power: String {
        switch host.host?.power?.kind {
        case "ac": return "市电"
        case "ups": return "UPS 供电" + (host.host?.power?.percent.map { " \($0)%" } ?? "")
        case "battery": return "电池供电" + (host.host?.power?.percent.map { " \($0)%" } ?? "")
        default: return "—"
        }
    }
}

struct ServerLoadCard: View {
    let host: HostStatus
    var body: some View {
        ServerCard(title: "负载 · 内存 · 温度", icon: "gauge.with.dots.needle.33percent") {
            let load = host.host?.load
            let mem = host.host?.memory
            HStack {
                metric("1 分钟", ServerText.number(load?.m1, 2))
                metric("5 分钟", ServerText.number(load?.m5, 2))
                metric("15 分钟", ServerText.number(load?.m15, 2))
                metric("每核", ServerText.number(load?.per_core_5m, 2))
            }
            let points = (host.history ?? []).compactMap { p -> (Date, Double)? in
                guard let d = ServerDates.parse(p.at), let v = p.load5 else { return nil }
                return (d, v)
            }
            if points.count >= 2 {
                Chart(points, id: \.0) { p in
                    LineMark(x: .value("时间", p.0), y: .value("5 分钟负载", p.1)).interpolationMethod(.monotone)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 90)
            }
            Divider()
            HStack {
                metric("内存压力", pressure(mem?.pressure))
                metric("可用", mem?.free_pct.map { "\(Int($0))%" } ?? "—")
                metric("交换区", mem?.swap_used_gb.map { String(format: "%.1f GB", $0) } ?? "—")
                metric("总内存", mem?.total_gb.map { String(format: "%.0f GB", $0) } ?? "—")
            }
            Divider()
            let t = host.host?.thermal
            HStack {
                metric("CPU 温度", HostThermal.text(t?.cpu_temp_c), tint: ServerText.temperatureColor(t?.cpuLevel))
                metric("GPU 温度", HostThermal.text(t?.gpu_temp_c), tint: ServerText.temperatureColor(t?.gpuLevel))
                metric("热警告", heat(t), tint: t?.overheated == true ? .red : .primary)
                metric("降频", throttle(t), tint: t?.overheated == true ? .red : .primary)
            }
            if t?.overheated == true {
                Label("Mac mini 过热，系统已经降频", systemImage: "thermometer.high")
                    .font(.caption.weight(.semibold)).foregroundStyle(.red)
            } else if let t, let hottest = t.hottest, hottest >= .warm {
                Label(t.warmReadings.map { "\($0.name) \(HostThermal.text($0.celsius)) \($0.level.word)" }.joined(separator: "，"),
                      systemImage: hottest == .hot ? "thermometer.high" : "thermometer.medium")
                    .font(.caption.weight(.semibold)).foregroundStyle(ServerText.temperatureColor(hottest))
            } else if t?.cpu_temp_c == nil && t?.gpu_temp_c == nil {
                Text("暂时读不到温度：Mac mini 上的 macmon 没装，或这次没读到。").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func metric(_ title: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// pmset's CPU speed limit when it reports one; otherwise a recorded thermal warning means macOS is throttling.
    private func throttle(_ t: HostThermal?) -> String {
        guard let t, t.available != false else { return "—" }
        if let limit = t.cpu_speed_limit, limit < 100 { return "限速 \(limit)%" }
        return t.overheated ? "已降频" : "无"
    }

    /// macOS's own thermal warning (pmset): overheated (throttling), a performance warning, or none.
    private func heat(_ t: HostThermal?) -> String {
        guard let t, t.available != false else { return "—" }
        if t.overheated { return "过热" }
        if !(t.performance_warning?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) { return "有告警" }
        return "无"
    }

    private func pressure(_ p: String?) -> String {
        switch p {
        case "normal": return "正常"
        case "warn": return "警告"
        case "critical": return "严重"
        default: return "—"
        }
    }
}

struct ServerDisksCard: View {
    let disks: [String: HostDisk?]
    // Same names as 需要处理 and the Mac's volume rows (StorageVolume.layout in PortSightKit).
    private let order = AttentionItems.diskNames.map(\.key)
    private let names = Dictionary(uniqueKeysWithValues: AttentionItems.diskNames.map { ($0.key, $0.name) })

    var body: some View {
        ServerCard(title: "磁盘", icon: "internaldrive") {
            let keys = order.filter { disks[$0] != nil } + disks.keys.filter { !order.contains($0) && $0 != "local_fallback" }.sorted()
            ForEach(keys, id: \.self) { key in
                let d = disks[key] ?? nil
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(names[key] ?? key).font(.subheadline)
                        Spacer()
                        if d?.mounted == true {
                            Text("剩 \(ServerText.number(d?.free_gb, 0)) GB / 共 \(ServerText.number(d?.total_gb, 0)) GB")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        } else {
                            Text("未挂载").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if d?.mounted == true, let used = d?.used_pct {
                        ProgressView(value: min(max(used / 100, 0), 1)).tint(used > 90 ? .red : used > 80 ? .orange : .accentColor)
                    }
                }
            }
            if let fb = disks["local_fallback"] ?? nil, (fb.files ?? 0) > 0 || (fb.blocked ?? 0) > 0 {
                Text("本机回退目录待合并 \(fb.files ?? 0) 个文件（\(ServerText.number(fb.mb, 1)) MB）" + ((fb.blocked ?? 0) > 0 ? "，\(fb.blocked ?? 0) 个被拦下" : ""))
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

struct ServerHeartbeatsCard: View {
    let beats: [HostHeartbeat]
    var body: some View {
        ServerCard(title: "运行程序与采集器", icon: "waveform.path.ecg") {
            let shown = beats.filter { $0.state != "not_installed" }
            ForEach(shown) { b in
                HStack(spacing: 10) {
                    ServerStateDot(state: b.state)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ServerText.name(b.name)).font(.subheadline)
                        if let note = note(b) { Text(note).font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(ServerText.state(b.state)).font(.caption.weight(.semibold)).foregroundStyle(ServerText.color(b.state))
                        Text(ServerDates.age(minutes: b.age_min)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            let hidden = beats.count - shown.count
            if hidden > 0 {
                Text("另有 \(hidden) 项未安装（\(beats.filter { $0.state == "not_installed" }.map { ServerText.name($0.name) }.joined(separator: "、"))）")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func note(_ b: HostHeartbeat) -> String? {
        var parts: [String] = []
        if b.phase == "sealed" { parts.append("保险箱封存中，只写心跳") }
        if b.phase == "stopped" { parts.append("停止文件在") }
        if b.behind == true { parts.append("落后：最后 \(b.last_session ?? "—")，应到 \(b.expected_session ?? "—")") }
        if let s = b.status, s != "ok" { parts.append("上次状态 \(s)") }
        if b.kind == "sleeve", let until = b.valid_until { parts.append("有效到 \(ServerDates.clock(ServerDates.parse(until)))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct ServerAlertsCard: View {
    let active: [HostActiveAlert]
    let recent: [HostEvent]
    var body: some View {
        ServerCard(title: "告警", icon: "bell.badge") {
            if active.isEmpty {
                Label("现在没有告警", systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(.green)
            }
            ForEach(active) { a in
                HStack(alignment: .top, spacing: 10) {
                    ServerStateDot(state: a.severity).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.title ?? a.key).font(.subheadline)
                        Text("从 \(ServerDates.clock(ServerDates.parse(a.since))) 起").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if !recent.isEmpty {
                Divider()
                Text("最近").font(.caption).foregroundStyle(.secondary)
                ForEach(recent.prefix(12)) { e in
                    HStack(alignment: .top, spacing: 10) {
                        ServerStateDot(state: e.severity == "info" ? "ok" : e.severity).padding(.top, 5)
                        Text(e.title ?? e.id).font(.caption).lineLimit(2)
                        Spacer()
                        Text(ServerDates.clock(ServerDates.parse(e.at))).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct ServerQueueCard: View {
    let queue: HostQueue?
    let deadman: HostDeadman?
    let push: HostPush?
    let report: HostCollectorReport?
    var body: some View {
        ServerCard(title: "队列 · 外部心跳 · 采集日报", icon: "list.bullet.rectangle") {
            if let lock = queue?.heavy_lock {
                row("重任务锁", "\(lock.owner ?? "?") · \(ServerText.number(lock.held_hours, 1)) 小时" + (lock.alive == false ? " · 进程已不在" : ""))
            } else {
                row("重任务锁", "空闲")
            }
            if queue?.heavy_pause != nil { row("重任务暂停", "开（HEAVY_PAUSE）") }
            ForEach(queue?.stop_files ?? []) { f in
                row("停止文件", "\(f.name)（\(ServerDates.clock(ServerDates.parse(f.since)))）")
            }
            Divider()
            if deadman?.enabled == true {
                row("外部心跳", "开 · 最后成功 \(ServerDates.clock(ServerDates.parse(deadman?.last_ok)))"
                    + ((deadman?.consecutive_failures ?? 0) > 0 ? " · 连续失败 \(deadman?.consecutive_failures ?? 0) 次" : ""))
            } else {
                row("外部心跳", "未开启")
            }
            row("APNs 推送", push?.apns_enabled == true ? "Mac mini 已开" : "Mac mini 未开")
            Divider()
            if report?.available == true {
                row("采集日报", "\(report?.alert_count ?? 0) 条 · \(ServerDates.clock(ServerDates.parse(report?.generated_at)))")
                ForEach(Array((report?.alerts ?? []).prefix(4).enumerated()), id: \.offset) { _, text in
                    Text(text).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            } else {
                row("采集日报", "暂无")
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline).multilineTextAlignment(.trailing)
        }
    }
}

struct ServerJobsCard: View {
    let jobs: [String: HostJob]
    /// false when the host status could not read launchd.
    var available = true
    var body: some View {
        ServerCard(title: "定时任务（launchd）", icon: "clock.arrow.2.circlepath") {
            if !available || jobs.isEmpty {
                Text("暂无").font(.subheadline).foregroundStyle(.secondary)
            }
            let labels = available ? jobs.keys.sorted { (jobs[$0]?.loaded == true ? 0 : 1, $0) < (jobs[$1]?.loaded == true ? 0 : 1, $1) } : []
            ForEach(labels, id: \.self) { label in
                let j = jobs[label]
                HStack(spacing: 10) {
                    ServerStateDot(state: j?.state)
                    Text(label.split(separator: ".").last.map(String.init) ?? label).font(.subheadline)
                    Spacer()
                    Text(ServerText.state(j?.state) + ((j?.last_exit).map { $0 != "0" && $0 != "-" ? " · 退出 \($0)" : "" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: settings

/// 量化服务器 pairing and push. Shown in 设置 and as the sheet from the 服务器 tab.
struct ServerPairingForm: View {
    @ObservedObject private var store = ServerStore.shared
    @State private var url = ""
    @State private var code = ""
    @AppStorage(ServerPush.enabledKey) private var pushEnabled = false
    /// The sheet passes this to show the sample and close; 设置 leaves it out.
    var showSample: (() -> Void)?

    var body: some View {
        Form {
            Section {
                LabeledContent("状态") { ServerPairingStateLabel(state: store.pairingState) }
                TextField("服务器地址", text: $url, prompt: Text("https://mac-mini.xxxx.ts.net"))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .textContentType(.URL)
                SecureField("配对码", text: $code)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button { Task { if await store.pair(url: url, code: code) { code = "" } } } label: {
                    if store.busy { ProgressView() } else { Text(store.isPaired ? "重新配对" : "配对") }
                }
                .disabled(store.busy || url.trimmingCharacters(in: .whitespaces).isEmpty
                          || code.trimmingCharacters(in: .whitespaces).isEmpty)
                if let m = store.message { Text(m).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text("量化服务器（Mac mini）")
            } footer: {
                Text("在 Mac mini 上运行 python3 -m quant_system.relay pair 得到配对码，5 分钟内有效，只能用一次。只连 https:// 地址，手机上不用开 Tailscale 或 VPN。设备凭证只存在这台手机的钥匙串里。")
            }
            if store.isPaired {
                Section {
                    LabeledContent("已配对", value: store.baseURL)
                    Button("断开", role: .destructive) { Task { await store.forget() } }
                }
            }
            Section {
                Toggle("推送通知（APNs）", isOn: $pushEnabled)
                if let s = store.pushStatus { Text(s).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text("提醒（默认关闭）")
            } footer: {
                Text("打开后，Mac mini 的主机告警和量化告警经苹果推送到这台手机，Mac mini 上也要打开 APNs 开关（见安装说明）。推送只写告警类型和时间，点开会显示这条告警的详情和同类历史。Mac mini 失联时它自己发不了推送，那一条由 Healthchecks.io 经 ntfy App 发。")
            }
            if let showSample, !store.isPaired {
                Section { Button("查看样例", action: showSample) }
            }
        }
        .onAppear { if url.isEmpty { url = store.baseURL } }
        .onChange(of: pushEnabled) { _, on in
            Task {
                if on {
                    if !(await ServerPush.enable()) {
                        pushEnabled = false
                        store.pushStatus = "通知权限被拒绝：到 iOS 设置 → 通知 → PortSight 打开"
                    }
                } else {
                    await ServerPush.disable()
                }
            }
        }
    }
}

/// 未配对 / 已配对 / 令牌已交给服务器 / 需要重新配对
struct ServerPairingStateLabel: View {
    let state: RelayPairingState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(state.title)
        }
        .foregroundStyle(color)
    }

    private var icon: String {
        switch state {
        case .unpaired: "link"
        case .paired: "checkmark.circle.fill"
        case .pushDelivered: "bell.badge.fill"
        case .needsRepair: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .unpaired: .secondary
        case .paired, .pushDelivered: .green
        case .needsRepair: .orange
        }
    }
}

struct ServerSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ServerPairingForm(showSample: { ServerStore.shared.showSample(); dismiss() })
                .navigationTitle("服务器设置")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}

#Preview {
    ServerView()
        .environmentObject(PortfolioDemo())
        .environmentObject(TerminalDemo())
}
