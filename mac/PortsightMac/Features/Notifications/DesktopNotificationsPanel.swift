import SwiftUI
import PortSightKit

/// Text and controls sit directly on the window material, without a panel background.
struct DesktopNotificationsPanel: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @EnvironmentObject private var terminal: TerminalDemo
    @Environment(\.desktopSection) private var section
    /// Passed on into the notice sheet, like `demo`, so its link button reaches ContentView.
    @Environment(\.openNoticeLink) private var openNoticeLink
    @State private var severity = "全部"
    @State private var category = "全部类别"
    @State private var search = ""
    @State private var selectedNotice: DemoNotice?
    @State private var selectedAlert: TerminalAlert?

    /// Account notices and relay alerts in one list (alerts used to have their own rail page).
    private var filteredItems: [FeedItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return NotificationFeed.items(notices: demo.bellNotices(on: section), alerts: terminal.alerts).filter { item in
            (severity == "全部" || item.severity == severity)
                && (category == "全部类别" || item.category == category)
                && (query.isEmpty || item.title.localizedCaseInsensitiveContains(query)
                    || item.detail.localizedCaseInsensitiveContains(query))
        }
    }

    /// The category filter's titles: the fixed ones, then any other category a relay notice carries.
    private var categories: [String] {
        let extra = demo.allNotices.map(\.category).filter { !NotificationFeed.categories.contains($0) }
        return NotificationFeed.categories + extra.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    private func isRead(_ item: FeedItem) -> Bool {
        switch item.source {
        case .notice(let id): demo.read.contains(id)
        case .alert(let id): terminal.read.contains(id)
        }
    }

    private func open(_ item: FeedItem) {
        switch item.source {
        // The relay's notices once paired, the built-in ones before (the same list the rows came from).
        case .notice(let id): selectedNotice = demo.allNotices.first { $0.id == id }
        case .alert(let id): selectedAlert = terminal.alerts.first { $0.id == id }
        }
    }

    /// The context menu's 标为已读 / 标为未读.
    private func setRead(_ item: FeedItem, _ read: Bool) {
        switch item.source {
        case .notice(let id): if read { demo.read.insert(id) } else { demo.read.remove(id) }
        case .alert(let id): if read { terminal.read.insert(id) } else { terminal.read.remove(id) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls

            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(filteredItems) { item in
                        Button { open(item) } label: {
                            DesktopNotificationRow(notice: DemoNotice(id: item.id, title: item.title, detail: item.detail,
                                                                      severity: item.severity, category: item.category,
                                                                      time: item.time, owner: .all),
                                                   isRead: isRead(item),
                                                   isAcknowledged: { if case .notice(let id) = item.source { demo.acknowledged.contains(id) } else { false } }())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if isRead(item) {
                                Button("标为未读", systemImage: "envelope.badge") { setRead(item, false) }
                            } else {
                                Button("标为已读", systemImage: "envelope.open") { setRead(item, true) }
                            }
                        }
                        .accessibilityIdentifier(item.id)
                        .accessibilityValue(isRead(item) ? "已读" : "未读")
                    }
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.vertical, 0, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollEdgeEffectHidden(true, for: .all)
            .accessibilityIdentifier("notifications_list")
            .overlay {
                if filteredItems.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bell").font(.title2)
                        Text("没有匹配的通知").font(.headline)
                        Text("试试其他级别或关键词。").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("notifications_panel")
        .closesForPush($selectedNotice)
        .sheet(item: $selectedNotice) { notice in
            DesktopSheetContainer(title: "通知详情", width: 520, height: 480, showsTitleBar: false) {
                DemoNoticeDetail(notice: notice)
            }
            .environmentObject(demo)
            .environment(\.openNoticeLink, openNoticeLink)
        }
        .closesForPush($selectedAlert)
        .sheet(item: $selectedAlert) { alert in
            DesktopSheetContainer(title: "告警详情", width: 520, height: 480, showsTitleBar: false) {
                DesktopAlertDetail(alert: alert)
            }
            .environmentObject(terminal)
        }
    }

    private var controls: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("搜索通知", text: $search)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("notifications_search")
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: Capsule())
        
                HStack(spacing: 8) {
                    filterButton("全部", value: "全部")
                    filterButton("严重", value: "critical")
                    filterButton("警告", value: "warning")
                    filterButton("信息", value: "info")
                    Spacer(minLength: 0)
                    DesktopCapsuleMenu(title: "类别", value: category, selection: $category) {
                        Text("全部类别").tag("全部类别")
                        Divider()
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("notifications_category")
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)
    }

    private func filterButton(_ title: String, value: String) -> some View {
        Button { severity = value } label: {
            Text(title)
                .font(.system(size: 14))
                .fontWeight(severity == value ? .semibold : .regular)
                .foregroundStyle(severity == value ? .primary : .secondary)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("notifications_filter_" + value)
        .accessibilityAddTraits(severity == value ? .isSelected : [])
    }
}
