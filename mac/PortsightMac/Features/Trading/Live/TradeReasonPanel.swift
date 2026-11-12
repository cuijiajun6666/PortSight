//
//  TradeReasonPanel.swift
//  PortsightMac
//
//  交易理由 in the right column of the 实时 page's trade card (LiveTradeCard): the G395 理由卡 (GET /journal,
//  JournalStore) for this coin and direction while the trade was open, matched by time (cards carry no trade id).
//  While the relay keeps the journal closed (404) it says 「交易理由卡尚未开放」 instead of an error. A long list
//  shows the opening card and the newest ones, with the rest counted by kind. Sealed cards carry no return, P&L or
//  IC, and none is worked out here.
//

import SwiftUI
import PortSightKit

struct TradeReasonPanel: View {
    let symbol: String
    let side: BacktestSide?
    /// The trade's id: cards carrying it (trade_id) are matched exactly.
    let tradeID: String?
    /// Opening time and close (or now, for an open position), epoch milliseconds.
    let start: Double
    let end: Double

    /// Unfolded cards; nil until the first click, when only the first card is unfolded.
    @State private var expanded: Set<String>?
    @State private var showsAll = false
    /// Pairing, unpairing or pairing again restarts the reading below at once.
    @ObservedObject private var server = ServerStore.shared

    private var store: JournalStore { .shared }
    /// Cards listed before the rest are folded into a count.
    private static let keep = 6

    var body: some View {
        let state = store.state
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("交易理由").font(.system(size: 12, weight: .semibold))
                Text("按币种、方向和时间对应").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            if let note = store.offlineNote {
                Label(note, systemImage: "wifi.slash").font(.system(size: 11)).foregroundStyle(DesktopTheme.orange)
            }
            if let journal = store.journal {
                cardList(journal)
            } else if let text = state.placeholder {
                placeholder(title: text.title, detail: text.detail, loading: state.isLoading, retry: state.canRetry)
            }
            Text(JournalFormat.caution).font(.system(size: 10)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Read when a trade is chosen, then again every few minutes while its card stays open, so new cards (and
        // the relay's switch opening) show up without choosing the trade again.
        .task(id: "\(symbol)|\(start)|\(server.pairingState)") {
            while !Task.isCancelled {
                await store.load()
                try? await Task.sleep(for: .seconds(JournalStore.freshFor))
            }
        }
        .onChange(of: start) {
            expanded = nil
            showsAll = false
        }
    }

    @ViewBuilder
    private func cardList(_ journal: TradeJournal) -> some View {
        let all = journal.cards(symbol: symbol, side: side, tradeID: tradeID, from: start, to: end)
        if all.isEmpty {
            placeholder(title: "这笔交易没有理由卡", detail: journal.emptyReason(symbol: symbol, start: start))
        } else {
            let condensed = TradeJournal.condensed(all, keep: Self.keep)
            let shown = showsAll ? all : condensed.cards
            if let note = journal.earlierNote(start) {
                Label(note, systemImage: "clock.arrow.circlepath").font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if condensed.hidden > 0 {
                HStack(alignment: .firstTextBaseline) {
                    Text("共 \(all.count) 张 · " + TradeJournal.kindSummary(all))
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button(showsAll ? "只看首尾" : "显示全部") { withAnimation(.smooth) { showsAll.toggle() } }
                        .buttonStyle(.link).font(.system(size: 11))
                }
            }
            ForEach(Array(shown.enumerated()), id: \.element.key) { index, card in
                if !showsAll, condensed.hidden > 0, index == 1 {
                    Text("… 中间 \(condensed.hidden) 张未列出").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                let open = binding(card.key, first: shown.first?.key)
                DisclosureGroup(isExpanded: open) {
                    ReasonCardDetail(card: card).padding(.top, 6)
                } label: {
                    ReasonCardHeader(card: card, expanded: open.wrappedValue)
                }
            }
        }
    }

    private func binding(_ key: String, first: String?) -> Binding<Bool> {
        let initial: Set<String> = first.map { [$0] } ?? []
        return Binding {
            (expanded ?? initial).contains(key)
        } set: { open in
            var next = expanded ?? initial
            if open { next.insert(key) } else { next.remove(key) }
            expanded = next
        }
    }

    private func placeholder(title: String, detail: String?, loading: Bool = false, retry: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "text.document").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12))
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if retry {
                Button("重试") { Task { await store.load(force: true) } }
                    .controlSize(.small)
            }
        }
    }
}

/// Kind, time, the 演练 / 封存期 marks and the one-sentence summary (two lines while folded): what a folded card
/// still shows.
private struct ReasonCardHeader: View {
    let card: JournalCard
    let expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(card.action?.title ?? JournalAction.title(nil)).font(.system(size: 12, weight: .semibold))
                if card.placeholder { ReasonBadge(text: "演练", tint: DesktopTheme.orange) }
                if card.sealed == true { ReasonBadge(text: "封存期", tint: .secondary) }
                Spacer(minLength: 4)
                Text(card.tauMs.map(LiveFormat.time) ?? card.tau ?? "—")
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            if let summary = card.summary_zh, !summary.isEmpty {
                Text(summary).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Position before and after, the decision chain, factor contributions, sub-strategy shares, ranks and the note.
struct ReasonCardDetail: View {
    let card: JournalCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                if let action = card.action, action.w_before != nil || action.w_after != nil {
                    row("仓位", JournalFormat.weight(action.w_before) + " → " + JournalFormat.weight(action.w_after)
                        + (action.change.map { "（" + JournalFormat.weight($0) + "）" } ?? ""))
                }
                if let intent = card.chain?.l2?.intent, !intent.isEmpty { row("意图", intent) }
                if !card.tags.isEmpty { row("风控调整", card.tags.joined(separator: " · ")) }
            }
            .font(.system(size: 11)).monospacedDigit()
            if card.chain?.env?.clipped == true {
                Label("被硬约束截断", systemImage: "scissors").font(.system(size: 11)).foregroundStyle(DesktopTheme.orange)
            }

            let factors = card.topFactors
            if !factors.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("因子贡献").font(.system(size: 10)).foregroundStyle(.secondary)
                    ReasonFactorChart(factors: factors)
                }
            }

            let sleeves = card.attribution?.sleeveFractions ?? []
            if !sleeves.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("子策略占比").font(.system(size: 10)).foregroundStyle(.secondary)
                    ForEach(Array(sleeves.enumerated()), id: \.offset) { _, sleeve in
                        HStack(spacing: 6) {
                            Text(sleeve.name).lineLimit(1).frame(width: 70, alignment: .leading)
                            ProgressView(value: min(max(sleeve.fraction, 0), 1)).controlSize(.small)
                            Text(JournalFormat.share(sleeve.fraction)).monospacedDigit().frame(width: 34, alignment: .trailing)
                        }
                        .font(.system(size: 11))
                    }
                }
            }

            let scores = card.signals?.scores ?? []
            if !scores.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("截面排名").font(.system(size: 10)).foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                        ForEach(Array(scores.enumerated()), id: \.offset) { _, score in
                            GridRow {
                                Text(score.name ?? "—").monospaced().lineLimit(1).truncationMode(.middle)
                                Text(JournalFormat.number(score.value)).gridColumnAlignment(.trailing)
                                Text(score.rankText).gridColumnAlignment(.trailing)
                            }
                        }
                    }
                    .font(.system(size: 11)).monospacedDigit()
                }
            }

            if let note = card.attribution?.note, !note.isEmpty {
                Label(note, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let meta = metaLine {
                Text(meta).font(.system(size: 10)).foregroundStyle(.tertiary).monospaced()
                    .lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private var metaLine: String? {
        let parts = [card.book, card.model, card.trade_id, card.id].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The top factor contributions (at most 5) as one bar per factor: name, bar, signed value. Bars grow from zero
/// (the middle when some are negative), scaled to the largest.
private struct ReasonFactorChart: View {
    let factors: [JournalFactor]

    var body: some View {
        let values = factors.map { $0.contribution ?? 0 }
        let largest = values.map(abs).max() ?? 0
        let origin: ReasonBar.Origin = values.contains { $0 < 0 } ? (values.contains { $0 > 0 } ? .middle : .trailing) : .leading
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            ForEach(Array(factors.enumerated()), id: \.offset) { index, factor in
                let value = factor.contribution ?? 0
                GridRow {
                    Text(label(index, factor)).font(.system(size: 11)).lineLimit(1)
                        .frame(maxWidth: 90, alignment: .leading)
                    ReasonBar(fraction: largest > 0 ? value / largest : 0, origin: origin,
                              tint: value >= 0 ? DesktopTheme.blue : DesktopTheme.orange)
                        .frame(height: 12)
                    Text(JournalFormat.number(factor.contribution)).font(.system(size: 10)).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// The Chinese name; a repeated or missing one is numbered so it keeps its own row.
    private func label(_ index: Int, _ factor: JournalFactor) -> String {
        guard let name = factor.name_zh, !name.isEmpty else { return "因子 \(index + 1)" }
        let earlier = factors.prefix(index).contains { $0.name_zh == name }
        return earlier ? name + " (\(index + 1))" : name
    }
}

/// One bar of ReasonFactorChart: `fraction` (−1…1) of the half (or whole) width, from the zero line.
private struct ReasonBar: View {
    enum Origin { case leading, middle, trailing }

    let fraction: Double
    let origin: Origin
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width, height = geo.size.height
            let span = origin == .middle ? width / 2 : width
            let zero: CGFloat = switch origin {
            case .leading: 0
            case .middle: width / 2
            case .trailing: width
            }
            let length = max(span * CGFloat(min(abs(fraction), 1)), fraction == 0 ? 0 : 2)
            let x = fraction >= 0 ? zero : zero - length
            ZStack(alignment: .topLeading) {
                if origin == .middle {
                    Rectangle().fill(.quaternary).frame(width: 1, height: height).offset(x: zero - 0.5)
                }
                Capsule().fill(tint).frame(width: length, height: height * 0.7)
                    .offset(x: x, y: height * 0.15)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ReasonBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(tint.opacity(0.12), in: Capsule())
    }
}
