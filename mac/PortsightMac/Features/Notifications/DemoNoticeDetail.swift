import SwiftUI
import PortSightKit

/// A notice's page: the built-in notices before pairing, the relay's GET /notices after (RelayNotice.asNotice), with
/// the notice's facts, 确认已查看 when it asks for it, and a button to where its link points.
struct DemoNoticeDetail: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @Environment(\.openNoticeLink) private var openLink
    let notice: DemoNotice

    /// Only links the app knows get a button; anything else is left out without an error.
    private var link: RelayLink? { RelayLink(notice.link) }

    var body: some View {
        // Relay notices offer it only when they ask for it (requires_ack) and have not expired. The built-in notices
        // keep offering it as they always have (critical ones also wait for it on 总览's 需要处理).
        let asksForAck = notice.fromRelay ? notice.needsAcknowledgement() : true
        DesktopMessageDetail(
            severity: AlertSeverity(noticeSeverity: notice.severity),
            category: notice.category,
            categoryIcon: "bell",
            title: notice.title,
            message: notice.detail,
            meta: [notice.owner.rawValue, notice.time],
            facts: notice.facts.map { .init(label: $0.label, value: $0.value) },
            action: asksForAck
                ? .init(title: "确认已查看", doneTitle: "已确认", isDone: demo.acknowledged.contains(notice.id)) {
                    demo.acknowledged.insert(notice.id)
                }
                : nil,
            link: link.map { link in .init(title: link.title, icon: link.icon) { openLink(link) } },
            note: asksForAck ? ackNote : nil
        )
        .onAppear { demo.read.insert(notice.id) }
    }

    /// The IBKR banner on 总览 follows the gateway's state alone, so confirming this notice does not take it away.
    private var ackNote: String {
        link == .ibkrReauth
            ? "确认只表示已看过；总览顶部的 IBKR 授权提示要等重新授权完成后才消失。"
            : "确认后首页的对应提示消失；不会修改任何策略或交易状态。"
    }
}
