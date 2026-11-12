//
//  TerminalMoreView.swift
//  PortSight
//
//  更多 tab: AI and settings. Also holds the cloud, AI, remote and alert pages used elsewhere.
//

import SwiftUI
import PortSightKit

enum MoreRoute: Hashable {
    case alerts, ai, remote, vault
}

struct TerminalMoreView: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @EnvironmentObject private var terminal: TerminalDemo
    @Binding var path: [MoreRoute]
    @State private var showServerSettings = false
    @AppStorage(AppEdition.storageKey) private var familyEdition = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // Messages are in the bell's message center; 云盘 and 远程 are on the 服务器 tab.
                Section {
                    NavigationLink(value: MoreRoute.ai) { Label("AI", systemImage: "brain") }
                    NavigationLink(value: MoreRoute.vault) { Label("文件保险箱", systemImage: "lock.shield") }
                } header: {
                    Text("Mac mini")
                } footer: {
                    Text("这些页面的内容来自家里的 Mac mini。")
                }
                Section {
                    Button { demo.showSettings = true } label: { Label("通用设置", systemImage: "gearshape") }
                    Button { showServerSettings = true } label: { Label("服务器连接", systemImage: "link") }
                    Toggle(isOn: $familyEdition) { Label("家人版", systemImage: "figure.2.and.child.holdinghands") }
                } header: {
                    Text("设置")
                } footer: {
                    Text("家人版只保留照片：时间线、回忆、人物、地图和搜索，适合给家里人用。")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("更多")
            .sheet(isPresented: $showServerSettings) { ServerSettingsView() }
            .navigationDestination(for: MoreRoute.self) { route in
                switch route {
                case .alerts: TerminalAlertsView()
                case .ai: TerminalAIView()
                case .remote: TerminalRemoteView()
                case .vault: VaultEmbeddedView()
                }
            }
        }
    }
}

// MARK: - 告警

struct TerminalAlertsView: View {
    @EnvironmentObject private var terminal: TerminalDemo

    var body: some View {
        List {
            Section {
                Picker("严重程度", selection: $terminal.severity) {
                    Text("全部").tag(AlertSeverity?.none)
                    ForEach(AlertSeverity.allCases) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                if terminal.filtered.isEmpty {
                    ContentUnavailableView("没有符合条件的告警", systemImage: "bell.slash")
                }
                ForEach(terminal.filtered) { alert in
                    NavigationLink { TerminalAlertDetailView(alert: alert) } label: {
                        TerminalAlertRow(alert: alert, isRead: terminal.read.contains(alert.id))
                    }
                    .swipeActions(edge: .leading) {
                        Button { terminal.toggleRead(alert) } label: {
                            Label(terminal.read.contains(alert.id) ? "未读" : "已读",
                                  systemImage: terminal.read.contains(alert.id) ? "envelope.badge" : "envelope.open")
                        }
                        .tint(.blue)
                    }
                }
            } footer: {
                Text("严重 \(terminal.count(.critical)) · 警告 \(terminal.count(.warning)) · 信息 \(terminal.count(.info))")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("告警")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("类别", selection: $terminal.category) {
                        Text("全部类别").tag(AlertCategory?.none)
                        ForEach(AlertCategory.allCases) { Label($0.title, systemImage: $0.icon).tag(Optional($0)) }
                    }
                } label: {
                    Image(systemName: terminal.category == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("按类别筛选")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { terminal.markAllRead() } label: { Image(systemName: "checkmark.message") }
                    .disabled(terminal.unreadCount == 0)
                    .accessibilityLabel("全部已读")
            }
        }
    }
}

struct TerminalAlertDetailView: View {
    @EnvironmentObject private var terminal: TerminalDemo
    let alert: TerminalAlert

    var body: some View {
        MessageDetailLayout(
            severity: alert.severity,
            category: alert.category.title,
            categoryIcon: alert.category.icon,
            title: alert.title,
            detail: alert.detail,
            meta: [alert.source, TerminalFormat.relative(alert.at)],
            footnote: "告警只用于查看，App 不会停止、重启或修改任何任务。")
        .onAppear { terminal.read.insert(alert.id) }
    }
}

// MARK: - 云盘

struct TerminalCloudView: View {
    private let library = DemoTerminalData.cloud
    @ObservedObject private var store = ServerStore.shared
    /// The same /host disks as the 服务器 page (the sample until paired).
    private var volumes: [StorageVolume] { store.volumes ?? [] }

    var body: some View {
        List {
            Section {
                TerminalHero(eyebrow: "Immich 照片库", value: library.photos.formatted() + " 张",
                             detail: library.videos.formatted() + " 段视频 · " + TerminalFormat.gigabytes(library.librarySizeGB)) {
                    HStack(spacing: 10) {
                        Button {} label: { Label("上传照片", systemImage: "photo.badge.plus").frame(maxWidth: .infinity) }
                        Button {} label: { Label("打开 Immich", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.glass).controlSize(.large)
                    .disabled(true)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 8, trailing: 4))
            } footer: {
                Text("Mac mini 到位并填写 Immich 地址后可用。")
            }

            // Same rule as 需要处理: only a photos disk the host reports as unmounted.
            if store.volumes != nil, (store.host?.disks?["photos"] ?? nil)?.mounted == false {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("照片盘未挂载").font(.subheadline.weight(.semibold))
                            Text("新上传会暂存在内置盘，挂载后再迁移。").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "externaldrive.badge.exclamationmark").foregroundStyle(.orange)
                    }
                }
            }

            Section("相簿") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                    ForEach(library.albums) { album in
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.quaternary)
                                .aspectRatio(4 / 3, contentMode: .fit)
                                .overlay { Image(systemName: album.symbol).font(.title2).foregroundStyle(.secondary) }
                            Text(album.name).font(.subheadline.weight(.semibold))
                            Text(album.count.formatted() + " 项").font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("存储") {
                if volumes.isEmpty {
                    Text("暂无磁盘数据").foregroundStyle(.secondary)
                } else {
                    ForEach(volumes) { TerminalVolumeRow(volume: $0) }
                }
            }

            Section("文件传输") {
                Label("手机和 Mac mini 都连上 Tailscale", systemImage: "network")
                Label("在「文件」App 连接服务器 smb://" + TerminalPlaceholders.host, systemImage: "folder.badge.plus")
                Label("照片交给 Immich，大文件放三星 T7", systemImage: "externaldrive")
            }
            .font(.subheadline)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("云盘")
    }
}

// MARK: - AI

/// The AI services, and the built-in 值班建议 / 每日复盘 paired or not (no AI analysis on the relay yet).
struct TerminalAIView: View {
    var body: some View {
        List {
            Section {
                ForEach(DemoTerminalData.aiServices) { service in
                    if service.id == "qa" {
                        NavigationLink { TerminalAIAskView() } label: { serviceRow(service) }
                    } else {
                        serviceRow(service)
                    }
                }
            } header: {
                Text("私有 AI 服务器")
            } footer: {
                Text("AI 服务器还没有给 App 的只读令牌，App 不保存管理员密码。")
            }

            Section("值班建议") {
                ForEach(DemoTerminalData.aiSuggestions) { suggestion in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(suggestion.title, systemImage: suggestion.category.icon).font(.subheadline.weight(.semibold))
                        Text(suggestion.reason).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                ForEach(DemoTerminalData.review.points, id: \.self) { point in
                    Text(point).font(.subheadline)
                }
            } header: {
                Text("每日复盘")
            } footer: {
                Text(DemoTerminalData.review.headline)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("AI")
    }

    private func serviceRow(_ service: AIService) -> some View {
        HStack(spacing: 12) {
            Image(systemName: service.icon).foregroundStyle(.blue).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.title).font(.subheadline.weight(.semibold))
                Text(service.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            TerminalPendingBadge()
        }
    }
}

/// AI · 资料问答: the ask field stays off until the AI server grants a read-only token.
struct TerminalAIAskView: View {
    /// Same three questions as the Mac 资料问答 page.
    static let samplePrompts = ["19b 订单流集成用了哪些特征？", "上周股票模拟盘为什么跑赢 SPY？", "forward15m 采集器以前出过什么问题？"]

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "sparkle.magnifyingglass").foregroundStyle(.secondary)
                    TextField("问问自己的笔记、研报和代码…", text: .constant(""))
                        .disabled(true)
                }
            } footer: {
                Text("AI 服务器还没有给 App 的只读令牌，接入后才能提问。")
            }
            Section("可以这样问") {
                ForEach(Self.samplePrompts, id: \.self) { prompt in
                    Label(prompt, systemImage: "text.bubble").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("资料问答")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 远程

struct TerminalRemoteView: View {
    var body: some View {
        List {
            ForEach(DemoTerminalData.remoteEntries) { entry in
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: entry.icon)
                            .font(.title2).foregroundStyle(entry.isPrimary ? .blue : .secondary)
                            .frame(width: 44, height: 44)
                            .background((entry.isPrimary ? Color.blue : Color.secondary).opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(entry.title).font(.headline)
                                if entry.isPrimary {
                                    Text("首选").font(.caption2.weight(.semibold)).foregroundStyle(.blue)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(.blue.opacity(0.12), in: Capsule())
                                }
                            }
                            Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                            Text(entry.address).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                        }
                    }
                    Button(entry.isPrimary ? "连接" : "打开") {}
                        .disabled(true)
                }
            }
            Section {
                Label("两台都是 Apple 芯片且 macOS 14 以上时，屏幕共享可选「高性能」模式。", systemImage: "bolt")
                Label("UU 远程只作应急备用，平时保持关闭。", systemImage: "lifepreserver")
            } footer: {
                Text("只打开对应的 App，PortSight 自己不实现远程桌面协议。")
            }
            .font(.subheadline)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("远程")
    }
}
