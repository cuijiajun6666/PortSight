//
//  ServerEventDetailView.swift
//  PortSight
//
//  The message page for a tapped relay push. The push carries only its title, body and `event_id`; the event's
//  severity, category, source and details come from the synced GET /alerts (synced once more if it is not there
//  yet). When the event still cannot be found, the page shows the push's own title and body.
//  Earlier occurrences of the same kind of alert (same id before "@") are listed below.
//
//  Where a tapped push opens (PushRoute): with nothing else on screen in 完整版, 消息中心 opens and pushes the
//  event's page; when another sheet or cover is up (it would block 消息中心), and in 家人版, the event's page is
//  presented over whatever is on top. A push whose event_id is a notice id (GET /notices, e.g. a 量化保护检查)
//  opens that notice's page the same way instead (ContentView looks it up first).
//
//  A notice's button (RelayLink) goes through NoticeLinkRoute: ContentView closes 消息中心 or the page shown over
//  the top and switches to the tab the link names.
//

import SwiftUI
import UIKit
import Observation
import SwiftData
import PortSightKit

/// What a tapped push opens: a relay alert (looked up in /alerts by its page) or a notice already found in /notices.
enum PushTarget: Hashable, Identifiable {
    case event(PushEventRef)
    case notice(RelayNotice)

    var id: String {
        switch self {
        case .event(let ref): "event:" + ref.id
        case .notice(let notice): "notice:" + notice.id
        }
    }

    // RelayNotice is not Hashable; the id is what tells two pages apart.
    static func == (lhs: PushTarget, rhs: PushTarget) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A tapped push on its way to the screen. The notification delegate sets `pending`; the edition on screen takes
/// it at once (ContentView in 完整版, AppEditionRoot in 家人版), so a push never waits to open later by surprise.
@MainActor @Observable
final class PushRoute {
    static let shared = PushRoute()
    var pending: PushEventRef?
    /// Handed to 消息中心, which pushes the event's (or notice's) page and clears it.
    var forMessageCenter: PushTarget?
    /// 消息中心 is on screen (set by it on appear / disappear). showNotifications alone can be true while the sheet
    /// never came up (asked for behind another sheet).
    var messageCenterOnScreen = false

    /// Screens presented over the key window's root, not counting one on its way out (0: the tabs are in front).
    static func modalDepth() -> Int {
        var depth = 0
        var top = keyWindow?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed {
            depth += 1
            top = next
        }
        return depth
    }

    /// Presents the event's (or notice's) page as a sheet over the top screen; retried for a few seconds while the
    /// window or a running transition is not ready (a cold launch from the push). A notice page needs the app's
    /// PortfolioDemo (已读 / 已确认) and model container, which a UIKit-presented page does not inherit.
    static func presentOverTop(_ target: PushTarget, demo: PortfolioDemo? = nil, terminal: TerminalDemo? = nil,
                               container: ModelContainer? = nil) {
        Task {
            for _ in 0..<25 {
                if tryPresent(target, demo: demo, terminal: terminal, container: container) { return }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private static func tryPresent(_ target: PushTarget, demo: PortfolioDemo?, terminal: TerminalDemo?,
                                   container: ModelContainer?) -> Bool {
        guard var top = keyWindow?.rootViewController else { return false }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        guard !top.isBeingPresented, !top.isBeingDismissed, top.transitionCoordinator == nil else { return false }
        let host = OverTopHost(rootView: AnyView(EmptyView()))
        var page = AnyView(PushedEventSheet(target: target, hasDemo: demo != nil) { [weak host] in
            host?.dismiss(animated: true)
        })
        if let demo { page = AnyView(page.environmentObject(demo)) }
        if let terminal { page = AnyView(page.environmentObject(terminal)) }
        if let container { page = AnyView(page.modelContainer(container)) }
        host.rootView = page
        top.present(host, animated: true)
        return true
    }

    /// Closes the pages presentOverTop put up (and anything above them), so a notice's link can show its tab.
    /// SwiftUI's own sheets are closed through their bindings instead.
    static func dismissOverTop() {
        var top = keyWindow?.rootViewController
        while let current = top, let next = current.presentedViewController {
            if next is OverTopHost {
                if !next.isBeingDismissed { current.dismiss(animated: true) }
                return
            }
            top = next
        }
    }

    private static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.sorted { rank($0) < rank($1) }.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    private static func rank(_ scene: UIWindowScene) -> Int {
        switch scene.activationState {
        case .foregroundActive: 0
        case .foregroundInactive: 1
        default: 2
        }
    }
}

/// The page presentOverTop puts up; its own type so dismissOverTop finds it in the presented chain.
private final class OverTopHost: UIHostingController<AnyView> {}

/// A notice's button on its way to the tabs (RelayLink: 总览's IBKR banner, 服务器, 交易 · 复盘 / 理由卡, 资产).
/// ContentView takes `pending`; `opened` counts every link so 总览 can also return to its top.
@MainActor @Observable
final class NoticeLinkRoute {
    static let shared = NoticeLinkRoute()
    var pending: RelayLink?
    private(set) var opened = 0

    func open(_ link: RelayLink) {
        pending = link
        opened += 1
    }
}

/// The event's or notice's page on its own, for a push that arrives while something else is presented (or in 家人版).
private struct PushedEventSheet: View {
    let target: PushTarget
    /// A notice page reads and writes PortfolioDemo; without it (家人版 never opens notices) nothing is shown.
    let hasDemo: Bool
    let close: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch target {
                case .event(let ref): ServerEventDetailView(ref: ref)
                case .notice(let notice):
                    if hasDemo { DemoNoticeDetail(notice: notice.asNotice()) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close, action: close) }
            }
        }
    }
}

struct ServerEventDetailView: View {
    let ref: PushEventRef
    @ObservedObject private var store = ServerStore.shared
    /// The lookup and the push it belongs to: a second push opened over this page shows a fresh lookup, never the
    /// first push's event.
    @State private var looked: (id: String, result: RelayEventLookup)?

    private var lookup: RelayEventLookup? { looked?.id == ref.id ? looked?.result : nil }

    var body: some View {
        Group {
            if let event = lookup?.event {
                let category = event.category.flatMap(AlertCategory.init(rawValue:))
                MessageDetailLayout(
                    severity: AlertSeverity(noticeSeverity: event.severity ?? "info"),
                    category: category?.title ?? event.category ?? "告警",
                    categoryIcon: category?.icon ?? "bell",
                    title: event.title ?? ref.headline,
                    detail: ref.body,
                    meta: [event.source, ServerDates.parse(event.at).map { ServerDates.clock($0) }].compactMap { $0 },
                    facts: event.detailFacts.map { .init(label: $0.label, value: $0.value) },
                    history: store.history(of: event).prefix(10).map {
                        .init(label: ServerDates.clock(ServerDates.parse($0.at)),
                              value: AlertSeverity(noticeSeverity: $0.severity ?? "info").title)
                    },
                    historyTitle: "同类告警（近 7 天）",
                    footnote: "告警只用于查看，App 不会停止、重启或修改任何任务。")
            } else if let lookup {
                // The push's own text: no event id (the evening digest), or the event could not be read.
                let isNotice = if case .noEvent = lookup { true } else { false }
                MessageDetailLayout(
                    severity: ref.severity,
                    category: isNotice ? "通知" : "告警",
                    categoryIcon: "bell",
                    title: ref.headline,
                    detail: ref.body,
                    footnote: lookup.fallbackNote)
            } else {
                ProgressView("正在读取告警…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: ref.id) {
            let id = ref.id
            let result = await store.lookUpEvent(ref)
            // A newer push replaced this one while it was looking up: its own task writes the result.
            guard !Task.isCancelled else { return }
            looked = (id, result)
        }
    }
}
