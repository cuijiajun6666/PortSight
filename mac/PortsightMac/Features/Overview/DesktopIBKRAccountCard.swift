//
//  DesktopIBKRAccountCard.swift
//  PortsightMac
//
//  资产 · 概览's 「IBKR 个人账户」: the personal IBKR account as the Mac mini reads it through IB Gateway (GET /account's
//  personal_ibkr, IBKRStore; read-only, nothing here can place an order). Shown only once a relay is paired. The
//  figures are called live only while IBKRStore says so; otherwise 「非实时 · 截至 …」 sits right next to them and they
//  are dimmed. The last read stays on screen offline, marked 「离线：显示 HH:mm 保存的数据」.
//
//  Reading: every 10 s (IBKRStore.runAssetsPolling) only while this card is on screen and the app is in front. The
//  Mac builds only the selected page, so leaving 资产 · 概览 removes the card and cancels the task; going to the
//  background cancels it too, and coming back restarts it with a read at once.
//

import SwiftUI
import PortSightKit

struct DesktopIBKRAccountCard: View {
    private let ibkr = IBKRStore.shared
    @Environment(\.desktopAppActive) private var appActive

    var body: some View {
        DesktopCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    DesktopSectionTitle(title: "IBKR 个人账户", subtitle: subtitle)
                    Spacer()
                    Image(systemName: "building.columns").foregroundStyle(.secondary).accessibilityHidden(true)
                }
                if let account = ibkr.account.document {
                    // Live turns into 非实时 on the clock too (a read older than half a minute, e.g. left from before
                    // the page was last open), not only on a change in the store; the positions follow the figures.
                    TimelineView(.periodic(from: .now, by: 5)) { context in
                        let live = ibkr.isLive(now: context.date)
                        VStack(alignment: .leading, spacing: 14) {
                            figures(account, now: context.date)
                            if !live, let reason = ibkr.staleReason {
                                Text(reason).font(.system(size: 11)).foregroundStyle(DesktopTheme.orange)
                            }
                            notes
                            positions(account, live: live)
                        }
                    }
                } else {
                    placeholder
                    notes
                }
            }
        }
        .accessibilityIdentifier("ibkr_account_card")
        .task(id: appActive) {
            guard appActive else { return }
            await ibkr.runAssetsPolling()
        }
    }

    private var subtitle: String {
        if let tail = ibkr.account.document?.accountTail, !tail.isEmpty { return "尾号 " + tail + " · 经 Mac mini 只读" }
        return "经 Mac mini 只读"
    }

    // MARK: Figures

    private func figures(_ account: PersonalIBKR, now: Date) -> some View {
        let currency = account.currency ?? "USD"
        let delayed = ibkr.delayedNote(now: now)
        // Figures that are not live are dimmed, so they never read as the current balance.
        let tint: Color = delayed == nil ? .primary : .secondary
        return HStack(alignment: .top, spacing: 24) {
            DesktopStat(label: "净值", value: IBKRFormat.money(account.netValue), detail: currency, tint: tint)
            DesktopStat(label: "现金", value: IBKRFormat.money(account.cash), detail: currency, tint: tint)
            DesktopStat(label: "购买力", value: IBKRFormat.money(account.buyingPower), detail: currency, tint: tint)
            // The positions' own currencies: a sum is only shown when they all match the account's.
            if let total = account.unrealizedTotal, account.positions.allSatisfy({ ($0.currency ?? currency) == currency }) {
                DesktopStat(label: "未实现盈亏", value: IBKRFormat.signedMoney(total), detail: currency,
                            tint: delayed == nil ? DesktopTheme.pnlColor(total) : .secondary)
            }
            freshness(delayed)
                .fixedSize()
        }
    }

    @ViewBuilder private func freshness(_ delayed: String?) -> some View {
        if let delayed {
            Label(delayed, systemImage: "clock.badge.exclamationmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesktopTheme.orange)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(DesktopTheme.orange.opacity(0.1), in: Capsule())
                .accessibilityIdentifier("ibkr_delayed")
        } else {
            HStack(spacing: 6) {
                DesktopStatusDot(color: DesktopTheme.green)
                Text("实时").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .accessibilityIdentifier("ibkr_live")
        }
    }

    /// Why the figures may not be current: the gateway's state, and a saved copy shown offline.
    @ViewBuilder private var notes: some View {
        let gateway = ibkr.gatewayNote
        let saved = savedNote
        if gateway != nil || saved != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let gateway {
                    Label(gateway, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(DesktopTheme.orange)
                }
                if let saved {
                    Label(saved, systemImage: "wifi.slash").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11))
        }
    }

    private var savedNote: String? {
        guard ibkr.account.isSaved, let readAt = ibkr.account.readAt else { return nil }
        return "离线：显示 " + Self.clock(readAt) + " 保存的数据"
    }

    /// "14:20" today, else "11-09 14:20".
    private static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    // MARK: Positions

    @ViewBuilder private func positions(_ account: PersonalIBKR, live: Bool) -> some View {
        let currency = account.currency ?? "USD"
        if account.positions.isEmpty {
            Text("没有持仓").font(.system(size: 12)).foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 0) {
                GridRow {
                    Text("代码"); Text("数量"); Text("成本"); Text("市值"); Text("未实现盈亏")
                }
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(.bottom, 10)
                // By position: the same symbol may come twice (another currency or contract).
                ForEach(Array(account.positions.enumerated()), id: \.offset) { _, position in
                    let symbol = position.symbol ?? "—"
                    // A position in another currency says so next to its money.
                    let suffix = position.currency.map { $0 == currency ? "" : " " + $0 } ?? ""
                    Divider().gridCellUnsizedAxes(.horizontal).opacity(0.5)
                    GridRow {
                        HStack(spacing: 10) {
                            DesktopSymbol(symbol: symbol, crypto: position.secType?.uppercased() == "CRYPTO" || SymbolLogoStore.isCrypto(symbol), size: 30)
                            Text(symbol).font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(IBKRFormat.quantity(position.quantity))
                        Text(IBKRFormat.money(position.cost) + suffix).foregroundStyle(.secondary)
                        Text(IBKRFormat.money(position.marketValue) + suffix).fontWeight(.semibold)
                            .foregroundStyle(live ? Color.primary : .secondary)
                        // Not live: grey like the figures above, never in live P&L colours.
                        Text(IBKRFormat.signedMoney(position.unrealizedPnl) + suffix)
                            .foregroundStyle(live ? (position.unrealizedPnl.map { DesktopTheme.pnlColor($0) } ?? .secondary) : .secondary)
                    }
                    .font(.system(size: 12)).monospacedDigit()
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Nothing to show yet

    /// notOpen → 「IBKR 实时资产尚未开放」; {"available": false, "message"} → the relay's message; the rest as every
    /// relay page says them (正在读取…, 需要重新配对, 暂时读不到 …).
    private var placeholder: some View {
        let phase = ibkr.account.phase
        let text = phase.placeholder(notOpen: "IBKR 实时资产尚未开放") ?? (title: "正在读取…", detail: nil)
        return HStack(spacing: 12) {
            if phase.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "chart.bar.doc.horizontal").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(text.title).font(.system(size: 13, weight: .medium))
                if let detail = text.detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityIdentifier("ibkr_account_placeholder")
    }
}
