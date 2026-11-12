//
//  DesktopServerEventDetail.swift
//  PortsightMac
//
//  The page for a clicked relay push, same as iOS (ServerEventDetailView). The push carries only its title, body and
//  `event_id`; severity, category, source and details come from the synced GET /alerts (synced once more if the event
//  is not there yet). When it still cannot be found, the page shows the push's own title and body.
//  Earlier occurrences of the same kind of alert (same id before "@") are listed below.
//

import SwiftUI
import PortSightKit

struct DesktopServerEventDetail: View {
    let ref: PushEventRef
    @ObservedObject private var store = ServerStore.shared
    /// The lookup and the push it belongs to, so a newer push never shows an older push's event.
    @State private var looked: (id: String, result: RelayEventLookup)?

    private var lookup: RelayEventLookup? { looked?.id == ref.id ? looked?.result : nil }

    var body: some View {
        Group {
            if let event = lookup?.event {
                let category = event.category.flatMap(AlertCategory.init(rawValue:))
                DesktopMessageDetail(
                    severity: AlertSeverity(noticeSeverity: event.severity ?? "info"),
                    category: category?.title ?? event.category ?? "告警",
                    categoryIcon: category?.icon ?? "bell",
                    title: event.title ?? ref.headline,
                    message: ref.body,
                    meta: [event.source, ServerDates.parse(event.at).map { ServerDates.clock($0) }].compactMap { $0 },
                    facts: event.detailFacts.map { .init(label: $0.label, value: $0.value) },
                    history: store.history(of: event).prefix(10).map {
                        .init(label: ServerDates.clock(ServerDates.parse($0.at)),
                              value: AlertSeverity(noticeSeverity: $0.severity ?? "info").title)
                    },
                    historyTitle: "同类告警（近 7 天）",
                    note: "告警只用于查看，App 不会停止、重启或修改任何任务。")
            } else if let lookup {
                // The push's own text: no event id (the evening digest), or the event could not be read.
                let isNotice = if case .noEvent = lookup { true } else { false }
                DesktopMessageDetail(
                    severity: ref.severity,
                    category: isNotice ? "通知" : "告警",
                    title: ref.headline,
                    message: ref.body,
                    note: lookup.fallbackNote)
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
