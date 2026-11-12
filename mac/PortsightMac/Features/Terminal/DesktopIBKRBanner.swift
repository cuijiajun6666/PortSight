//
//  DesktopIBKRBanner.swift
//  PortsightMac
//
//  The IBKR re-authorization banner at the top of 总览 (IBKRStore.banner). IBKR wants a two-factor login every week;
//  重新授权 only asks the Mac mini to start it (POST /ibkr/reauth) and the user confirms in IBKR Mobile on the phone.
//  No login, password or token is ever asked for here. The banner follows the gateway's state alone, never a notice's
//  确认已查看: only state = connected takes it away. IBKRStore's short notice ("IBKR 已重新授权", "刚刚已发起…") shows
//  under it, or in its place, until it expires. The 6-second status polling lives on the page (DesktopTerminalOverview).
//

import SwiftUI
import PortSightKit

struct DesktopIBKRBanner: View {
    private let ibkr = IBKRStore.shared
    /// The banner applies only while a relay is paired (IBKRStore checks RelayNotices.usesRelay, read from here).
    @ObservedObject private var server = ServerStore.shared

    var body: some View {
        if ibkr.bannerVisible || ibkr.notice != nil {
            // The notice expires and the 重新授权 cooldown ends on the clock, not on a change in the store.
            // Every second while the 重新授权 countdown runs, else every 2 s.
            TimelineView(.periodic(from: .now, by: ibkr.banner()?.cooldownUntil != nil ? 1 : 2)) { context in
                content(now: context.date)
            }
            // Clear the notice once it has expired, so the clock above stops when there is no banner either.
            .task(id: ibkr.notice?.until) {
                guard let notice = ibkr.notice else { return }
                let left = notice.until.timeIntervalSinceNow
                if left > 0 { try? await Task.sleep(for: .seconds(left)) }
                guard !Task.isCancelled, ibkr.notice == notice else { return }
                ibkr.dismissNotice()
            }
        }
    }

    @ViewBuilder private func content(now: Date) -> some View {
        let banner = ibkr.banner(now: now)
        let notice = ibkr.notice.flatMap { $0.isShown(now: now) ? $0 : nil }
        if banner != nil || notice != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let banner { bannerView(banner, now: now) }
                if let notice { noticeView(notice) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bannerView(_ banner: IBKRBanner, now: Date) -> some View {
        let tint = banner.tone == .action ? DesktopTheme.orange : DesktopTheme.blue
        return HStack(spacing: 14) {
            Group {
                if banner.tone == .progress {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 38, height: 38)
            .background(tint.opacity(0.14), in: Circle())
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(banner.title).font(.system(size: 15, weight: .semibold))
                Text(detail(banner))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let wait = banner.cooldownText(now: now) {
                    Text(wait.replacingOccurrences(of: "IBKR Mobile", with: "手机上的 IBKR Mobile"))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(DesktopTheme.orange)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.smooth, value: wait)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            if banner.showsButton {
                Button { Task { await ibkr.reauthorize() } } label: {
                    HStack(spacing: 6) {
                        if ibkr.reauthInFlight { ProgressView().controlSize(.small) }
                        Text(banner.buttonTitle)
                    }
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(tint)
                .controlSize(.large)
                .disabled(!banner.buttonEnabled(now: now))
                .help("请 Mac mini 发起 IBKR 登录，然后在手机上的 IBKR Mobile 里确认")
                .accessibilityIdentifier("ibkr_reauth_button")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ibkr_banner")
    }

    /// The Mac has no IBKR Mobile, so the line under the title says the confirmation happens on the phone. A reason
    /// from the Mac mini (why the last login failed) is shown as it came.
    private func detail(_ banner: IBKRBanner) -> String {
        if let message = ibkr.status.document?.message, banner.detail == message { return message }
        switch banner.state {
        case .needsReauth: return "点击后请在手机上的 IBKR Mobile 里确认登录"
        case .loggingIn: return "Mac mini 正在登录，稍后在手机上的 IBKR Mobile 里确认"
        case .awaiting2FA: return "在手机上的 IBKR Mobile 里确认，确认后这里会自动更新"
        default: return banner.detail
        }
    }

    private func noticeView(_ notice: IBKRNotice) -> some View {
        let style = Self.style(notice.tone)
        return HStack(spacing: 8) {
            Image(systemName: style.icon).foregroundStyle(style.tint).accessibilityHidden(true)
            Text(notice.text).font(.system(size: 13, weight: .medium))
            Button { ibkr.dismissNotice() } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("关闭")
            .accessibilityLabel("关闭提示")
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(style.tint.opacity(0.1), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ibkr_notice")
    }

    private static func style(_ tone: IBKRNotice.Tone) -> (icon: String, tint: Color) {
        switch tone {
        case .success: ("checkmark.circle.fill", DesktopTheme.green)
        case .info: ("info.circle.fill", DesktopTheme.blue)
        case .warning: ("exclamationmark.triangle.fill", DesktopTheme.orange)
        }
    }
}
