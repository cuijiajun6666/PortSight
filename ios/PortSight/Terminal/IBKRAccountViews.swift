//
//  IBKRAccountViews.swift
//  PortSight
//
//  The personal IBKR account as the Mac mini sees it (PortSightKit's IBKRStore): the re-authorization banner at the
//  top of 总览. Read-only: the one thing the app can ask is 重新授权, which only makes the Mac mini start the login;
//  the user confirms it in IBKR Mobile. There is no IBKR login, password or token field anywhere. It shows nothing
//  before a relay is paired. The account's figures are on the 资产 pages themselves (AssetsTabView polls them).
//

import SwiftUI
import PortSightKit

// MARK: - 总览: re-authorization banner

/// IBKR wants a fresh two-factor login every week. Up while the state is needs_reauth / logging_in / awaiting_2fa;
/// only state = connected takes it away (confirming a notice does not). The short notices (「IBKR 已重新授权」,
/// 「刚刚已发起…」) show under it, or alone once it is gone, until they expire.
struct IBKRBannerSection: View {
    @ObservedObject private var server = ServerStore.shared
    private let ibkr = IBKRStore.shared

    var body: some View {
        let banner = ibkr.banner()
        let notice = ibkr.notice.flatMap { $0.isShown() ? $0 : nil }
        if banner != nil || notice != nil {
            Section {
                if let banner {
                    // Redrawn every second while the button is held back, so the countdown runs and the button
                    // comes back on its own.
                    if banner.cooldownUntil != nil {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            bannerRow(ibkr.banner(now: context.date) ?? banner, now: context.date)
                        }
                    } else {
                        bannerRow(banner, now: .now)
                    }
                }
                if let notice {
                    noticeRow(notice)
                        // Hide it when it expires (nothing else redraws the page then).
                        .task(id: notice) {
                            let wait = notice.until.timeIntervalSinceNow
                            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                            guard !Task.isCancelled, ibkr.notice == notice else { return }
                            withAnimation(.smooth) { ibkr.dismissNotice() }
                        }
                }
            }
            .listRowBackground(tint(banner: banner, notice: notice).opacity(0.12))
        }
    }

    private func bannerRow(_ banner: IBKRBanner, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon(banner))
                    .font(.title2)
                    .foregroundStyle(banner.tone == .action ? Color.orange : .blue)
                    .frame(width: 30)
                    .symbolEffect(.pulse, isActive: banner.tone == .progress)
                VStack(alignment: .leading, spacing: 3) {
                    Text(banner.title).font(.headline)
                    Text(banner.detail).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let wait = banner.cooldownText(now: now) {
                        Text(wait)
                            .font(.subheadline).foregroundStyle(.orange)
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.smooth, value: wait)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if banner.tone == .progress { ProgressView() }
            }
            .accessibilityElement(children: .combine)
            if banner.showsButton {
                Button {
                    Task { await ibkr.reauthorize() }
                } label: {
                    HStack(spacing: 8) {
                        if ibkr.reauthInFlight { ProgressView() }
                        Text(banner.buttonTitle)
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .tint(.orange)
                .disabled(!banner.buttonEnabled(now: now))
                .sensoryFeedback(.impact, trigger: ibkr.reauthInFlight) { _, started in started }
            }
        }
        .padding(.vertical, 4)
    }

    private func noticeRow(_ notice: IBKRNotice) -> some View {
        Label {
            Text(notice.text).font(.subheadline.weight(.medium))
        } icon: {
            Image(systemName: icon(notice)).foregroundStyle(color(notice))
        }
    }

    private func icon(_ banner: IBKRBanner) -> String {
        switch banner.state {
        case .loggingIn: "arrow.triangle.2.circlepath"
        case .awaiting2FA: "lock.iphone"
        default: "person.badge.key.fill"
        }
    }

    private func icon(_ notice: IBKRNotice) -> String {
        switch notice.tone {
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private func color(_ notice: IBKRNotice) -> Color {
        switch notice.tone {
        case .success: .green
        case .info: .blue
        case .warning: .orange
        }
    }

    /// The row background follows the banner, or the notice when it stands alone.
    private func tint(banner: IBKRBanner?, notice: IBKRNotice?) -> Color {
        if let banner { return banner.tone == .action ? .orange : .blue }
        return notice.map(color) ?? .clear
    }
}

/// When a copy kept for offline use was read: "14:20" today, else "11-09 14:20".
enum SavedClock {
    static func text(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
