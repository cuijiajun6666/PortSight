import SwiftUI
import PortSightKit

/// The next market event with a countdown: the relay's GET /calendar (next 14 days) once paired
/// (RelayMarket.calendarState / nextEvent), the built-in events before. An empty calendar is normal and reads
/// 「未来 14 天没有重要事件」, not as an error; the relay's message (why earnings dates are missing) sits at the bottom.
struct DesktopUpcomingEventCard: View {
    let scope: PortfolioScope

    var body: some View {
        DesktopCard(padding: 16) {
            // Only this card updates each second; the portfolio and charts do not.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let state = RelayMarket.calendarState(scope: scope, now: context.date)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        DesktopSectionTitle(title: "下一件重大事件")
                        Spacer()
                        Image(systemName: "calendar").foregroundStyle(.secondary)
                    }
                    if let event = RelayMarket.nextEvent(scope: scope, after: context.date) {
                        HStack {
                            Text(event.title).font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 4)
                            // The relay says what kind of event it is (宏观事件, 公司财报 …).
                            Text(state.isBuiltIn ? "日程" : event.category).font(.caption).foregroundStyle(.secondary)
                        }
                        countdown(event: event, now: context.date)
                        Text(event.date, format: .dateTime.month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    } else if state.isBuiltIn {
                        Text("暂无后续事件").font(.callout).foregroundStyle(.secondary)
                    } else {
                        DesktopMarketCardEmpty(isLoading: state.isLoading,
                                               title: state.emptyTitle ?? "未来 14 天没有重要事件",
                                               detail: state.emptyDetail)
                    }
                    DesktopMarketCardNotes(note: state.note, savedNote: state.savedNote)
                }
            }
        }
        .accessibilityIdentifier("upcoming_event_card")
        // The store keeps reads at least 5 minutes apart by itself; before pairing nothing is read.
        .task {
            guard RelayNotices.usesRelay else { return }
            await RelayMarket.calendar.load()
        }
    }

    private func countdown(event: MarketCalendarEvent, now: Date) -> some View {
        let time = EventCountdown(deadline: event.date, now: now)
        let values = [time.days, time.hours, time.minutes, time.seconds]
        let units = ["天", "时", "分", "秒"]
        return HStack(spacing: 12) {
            ForEach(0..<4) { index in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%02d", values[index]))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(units[index]).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("距\(event.title)还有 \(time.days) 天 \(time.hours) 小时 \(time.minutes) 分 \(time.seconds) 秒")
    }
}
