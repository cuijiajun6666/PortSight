//
//  TerminalMessageCenterView.swift
//  PortSight
//
//  The bell's message center: the account notices (the relay's GET /notices once paired, the built-in ones before)
//  and the server alerts in one list, filtered by severity and category (same feed as the Mac bell panel). Unread
//  counts live on the bell, not on a tab.
//

import SwiftUI
import PortSightKit

struct TerminalMessageCenterView: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @EnvironmentObject private var terminal: TerminalDemo
    @Environment(\.dismiss) private var dismiss
    @State private var severity = "全部"
    @State private var category = "全部类别"
    @State private var search = ""

    private var items: [FeedItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return NotificationFeed.items(notices: demo.notices, alerts: terminal.alerts).filter { item in
            (severity == "全部" || item.severity == severity)
                && (category == "全部类别" || item.category == category)
                && (query.isEmpty || item.title.localizedCaseInsensitiveContains(query)
                    || item.detail.localizedCaseInsensitiveContains(query))
        }
    }

    private var unread: Int { MessageCenter.unreadCount(demo: demo, terminal: terminal) }

    /// The filter's categories, plus any the relay's notices use that the built-in list lacks (复盘, 交易 …).
    private var categories: [String] {
        var all = NotificationFeed.categories
        for title in demo.notices.map(\.category) where !all.contains(title) { all.append(title) }
        return all
    }

    /// Why the relay's notices are missing or old: not open or not ready yet (「通知尚未接入」), unreadable, or a copy
    /// saved before going offline. nil before pairing and while they are fresh.
    private var noticesNote: String? {
        guard RelayNotices.usesRelay else { return nil }
        let store = RelayNotices.store
        if store.document == nil {
            guard !store.phase.isLoading, let text = store.phase.placeholder(notOpen: "通知尚未开放") else { return nil }
            return "通知：" + text.title
        }
        guard store.isSaved, let readAt = store.readAt else { return nil }
        return "离线：显示 " + SavedClock.text(readAt) + " 保存的通知"
    }

    @State private var pushedTarget: PushTarget?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if items.isEmpty {
                        ContentUnavailableView("没有匹配的消息", systemImage: "bell.slash", description: Text("换一个级别、类别或关键词。"))
                    }
                    ForEach(items) { item in
                        NavigationLink { detail(for: item) } label: { row(item) }
                            .swipeActions(edge: .leading) {
                                Button { toggleRead(item) } label: {
                                    Label(isRead(item) ? "未读" : "已读", systemImage: isRead(item) ? "envelope.badge" : "envelope.open")
                                }
                                .tint(.blue)
                            }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(demo.scope.rawValue) · \(unread) 条未读")
                        if let noticesNote { Text(noticesNote) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("严重程度", selection: $severity) {
                    Text("全部").tag("全部")
                    Text("严重").tag("critical")
                    Text("警告").tag("warning")
                    Text("信息").tag("info")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .navigationTitle("消息中心")
            .navigationBarTitleDisplayMode(.inline)
            // A tapped relay push lands here: its event's (or notice's) page on top of the list.
            .navigationDestination(item: $pushedTarget) { target in
                switch target {
                case .event(let ref): ServerEventDetailView(ref: ref)
                case .notice(let notice): DemoNoticeDetail(notice: notice.asNotice())
                }
            }
            .onChange(of: PushRoute.shared.forMessageCenter, initial: true) { _, target in
                guard let target else { return }
                PushRoute.shared.forMessageCenter = nil
                pushedTarget = target
            }
            // The relay's notices, fresh when the bell opens (the store reads at most every 30 s by itself).
            .task {
                guard RelayNotices.usesRelay else { return }
                await RelayNotices.store.load()
            }
            .searchable(text: $search, prompt: "搜索消息")
            // Rows slide in and out as the search or the level changes the list.
            .animation(.smooth, value: items.map(\.id))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("类别", selection: $category) {
                            Text("全部类别").tag("全部类别")
                            ForEach(categories, id: \.self) { Text($0).tag($0) }
                        }
                    } label: {
                        Image(systemName: category == "全部类别" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("按类别筛选")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { MessageCenter.markAllRead(demo: demo, terminal: terminal) } label: {
                        Image(systemName: "checkmark.message")
                    }
                    .disabled(unread == 0)
                    .accessibilityLabel("全部标为已读")
                    Button("完成") { dismiss() }
                }
            }
        }
        // On the whole stack, not the list: pushing an event's page must not count as leaving 消息中心.
        .onAppear { PushRoute.shared.messageCenterOnScreen = true }
        .onDisappear { PushRoute.shared.messageCenterOnScreen = false }
    }

    private func row(_ item: FeedItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.severity == "critical" ? "exclamationmark.octagon.fill"
                  : item.severity == "warning" ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(item.severity == "critical" ? .red : item.severity == "warning" ? .orange : .blue)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(isRead(item) ? .regular : .semibold))
                Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(item.category + " · " + item.time).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if !isRead(item) { Circle().fill(.blue).frame(width: 8, height: 8).padding(.top, 6).accessibilityLabel("未读") }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func detail(for item: FeedItem) -> some View {
        switch item.source {
        case .notice(let id):
            // The list's own notices: the relay's once paired, the built-in ones before.
            if let notice = demo.notices.first(where: { $0.id == id }) { DemoNoticeDetail(notice: notice) }
        case .alert(let id):
            if let alert = terminal.alerts.first(where: { $0.id == id }) { TerminalAlertDetailView(alert: alert) }
        }
    }

    private func isRead(_ item: FeedItem) -> Bool {
        switch item.source {
        case .notice(let id): demo.read.contains(id)
        case .alert(let id): terminal.read.contains(id)
        }
    }

    private func toggleRead(_ item: FeedItem) {
        switch item.source {
        case .notice(let id): if demo.read.contains(id) { demo.read.remove(id) } else { demo.read.insert(id) }
        case .alert(let id): if terminal.read.contains(id) { terminal.read.remove(id) } else { terminal.read.insert(id) }
        }
    }
}

/// Unread count and mark-all-read across both feeds, shared by the bell and the message center.
@MainActor
enum MessageCenter {
    static func unreadCount(demo: PortfolioDemo, terminal: TerminalDemo) -> Int {
        demo.notices.filter { !demo.read.contains($0.id) }.count + terminal.unreadCount
    }

    static func markAllRead(demo: PortfolioDemo, terminal: TerminalDemo) {
        demo.read.formUnion(demo.notices.map(\.id))
        terminal.markAllRead()
    }
}
