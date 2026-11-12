//
//  DesktopJournalPage.swift
//  PortsightMac
//
//  交易 · 理由卡: every G395 理由卡 the v4 shadow wrote in the last 7 days (GET /journal, JournalStore), newest first.
//  列表 groups them by decision round and opens one card on the right; 按天 and 按币 count the actions, and a click
//  there filters the list. Filters: 币种, 子策略, 动作. While the relay keeps the journal closed (404) the page says
//  「交易理由卡尚未开放」. Cards carry no return, P&L or IC, and the page shows only counts and the cards' own
//  fields: no result numbers before the sealed results open.
//

import SwiftUI
import Combine
import PortSightKit

enum JournalViewMode: String, CaseIterable, Hashable {
    case list = "列表", days = "按天", coins = "按币"
}

struct DesktopJournalPage: View {
    @State private var mode: JournalViewMode = .list
    @State private var filter = JournalFilter()
    @State private var selectedKey: String?
    /// Pairing, unpairing or pairing again restarts the reading below at once (only this is followed, not every
    /// change of the server store, so 2000 cards are not re-sorted on each host refresh).
    @State private var pairing = ServerStore.shared.pairingState

    private var store: JournalStore { .shared }
    private static let paneHeight: CGFloat = 540

    var body: some View {
        DesktopFullPage(maxWidth: 1_400, spacing: 22) {
            header
            if let journal = store.journal {
                notices(journal)
                controls(journal)
                switch mode {
                case .list: listPanes(journal)
                case .days: dayTable(journal)
                case .coins: coinTable(journal)
                }
            } else if let text = store.state.placeholder {
                placeholder(text.title, text.detail)
            }
            Text(JournalFormat.caution).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .onReceive(ServerStore.shared.$pairingState.removeDuplicates()) { pairing = $0 }
        .task(id: pairing) {
            while !Task.isCancelled {
                await store.load()
                try? await Task.sleep(for: .seconds(JournalStore.freshFor))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        let journal = store.journal
        var detail = "最近 7 天 · 每次真实成交（开仓、加减仓、平仓、反手）一张"
        if let journal {
            detail = "最近 7 天 · \(journal.cards.count) 张"
            if let asOf = journal.asOfMilliseconds { detail += " · 更新于 " + LiveFormat.time(asOf) }
        }
        return DesktopPageHeader(eyebrow: "交易 · 理由卡", title: "交易理由卡", detail: detail) { EmptyView() }
    }

    @ViewBuilder
    private func notices(_ journal: TradeJournal) -> some View {
        let sealed = journal.sealed == true || journal.cards.contains { $0.sealed == true }
        let rehearsal = journal.cards.contains(where: \.placeholder)
        let offline = store.offlineNote
        if sealed || rehearsal || journal.isTruncated || offline != nil {
            VStack(alignment: .leading, spacing: 6) {
                if let offline {
                    Label(offline, systemImage: "wifi.slash").foregroundStyle(DesktopTheme.orange)
                }
                if sealed {
                    Label("封存期：卡里没有收益、盈亏和 IC，\(LiveFeed.shadowUnsealDate) 之前不显示任何结果类数字。", systemImage: "lock.fill")
                }
                if rehearsal {
                    Label("标「演练」的卡是占位冻结期的演练数据，不是真实决策。", systemImage: "theatermasks")
                        .foregroundStyle(DesktopTheme.orange)
                }
                if let note = journal.truncationNote {
                    Label(note, systemImage: "clock.arrow.circlepath")
                }
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    // MARK: Controls

    private func controls(_ journal: TradeJournal) -> some View {
        let cards = journal.cards
        return VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
            DesktopCapsulePicker(title: "视图", options: JournalViewMode.allCases, selection: $mode) { $0.rawValue }
                .fixedSize().labelsHidden()
            Menu {
                Picker("币种", selection: $filter.coin) {
                    Text("全部币种").tag(String?.none)
                    ForEach(JournalBrowser.coins(in: cards), id: \.coin) { Text("\($0.coin)  ·  \($0.count) 张").tag(String?.some($0.coin)) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(filter.coin ?? "全部币种", systemImage: "bitcoinsign.circle")
            }
            .fixedSize()
            Menu {
                Picker("子策略", selection: $filter.sleeve) {
                    Text("全部子策略").tag(String?.none)
                    ForEach(JournalBrowser.sleeves(in: cards), id: \.name) { Text("\($0.name)  ·  \($0.count) 张").tag(String?.some($0.name)) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(filter.sleeve ?? "全部子策略", systemImage: "square.stack.3d.up")
            }
            .fixedSize()
            Menu {
                Picker("动作", selection: $filter.kind) {
                    Text("全部动作").tag(String?.none)
                    ForEach(JournalBrowser.kinds(in: cards), id: \.kind) { Text("\($0.title)  ·  \($0.count) 张").tag(String?.some($0.kind)) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(filter.kind.map { JournalAction.title($0) } ?? "全部动作", systemImage: "arrow.left.arrow.right")
            }
            .fixedSize()
            if JournalBrowser.books(in: cards).count > 1 || filter.book != nil {
                Menu {
                    Picker("账户", selection: $filter.book) {
                        Text("全部账户").tag(String?.none)
                        ForEach(JournalBrowser.books(in: cards), id: \.book) { Text("\($0.book)  ·  \($0.count) 张").tag(String?.some($0.book)) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(filter.book ?? "全部账户", systemImage: "person.crop.rectangle.stack")
                }
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
        // The day chip and 清除筛选 go on their own line, so the bar never runs past a narrow window.
        if filter.day != nil || !filter.isEmpty {
            HStack(spacing: 10) {
                if let day = filter.day {
                    Button { filter.day = nil } label: {
                        Label(Self.dayTitle(day), systemImage: "xmark.circle.fill")
                    }
                    .help("取消日期筛选")
                }
                Button("清除筛选") { filter = JournalFilter() }
            }
        }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    // MARK: 列表

    private func listPanes(_ journal: TradeJournal) -> some View {
        let shown = JournalBrowser.filtered(journal.cards, filter)
        let selected = shown.first { $0.key == selectedKey } ?? shown.first
        return HStack(alignment: .top, spacing: 14) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if shown.isEmpty {
                        placeholder("没有符合筛选的卡", "换一个筛选，或点 清除筛选。").padding(16)
                    }
                    ForEach(JournalBrowser.rounds(shown)) { round in
                        Section {
                            ForEach(round.cards, id: \.key) { card in
                                Button { selectedKey = card.key } label: {
                                    JournalRow(card: card, selected: card.key == selected?.key)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            roundHeader(round)
                        }
                    }
                }
            }
            .frame(minWidth: 220, maxWidth: .infinity)
            .frame(height: Self.paneHeight)
            .background(DesktopTheme.card, in: DesktopTheme.surfaceShape)
            .overlay { DesktopTheme.surfaceShape.strokeBorder(DesktopTheme.border, lineWidth: 1) }
            .clipShape(DesktopTheme.surfaceShape)

            ScrollView {
                if let selected {
                    JournalCardPane(card: selected).padding(16)
                } else {
                    placeholder("选一张卡", nil).padding(16)
                }
            }
            .frame(minWidth: 280, idealWidth: 400, maxWidth: 400)
            .frame(height: Self.paneHeight)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        // Keep the card on the right once it is shown: a refresh bringing a newer round does not swap it, and only
        // a card that leaves the list (filtered out) hands over to the first one.
        .onChange(of: shown.map(\.key), initial: true) { _, keys in
            if selectedKey == nil || !keys.contains(selectedKey ?? "") { selectedKey = keys.first }
        }
    }

    private func roundHeader(_ round: JournalRound) -> some View {
        HStack(spacing: 8) {
            Text(round.tauMs.map(LiveFormat.time) ?? round.tau ?? "时间不明").fontWeight(.semibold).monospacedDigit()
            Text("\(round.coins) 个币 · " + round.kinds.summary).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: 按天 / 按币

    private func dayTable(_ journal: TradeJournal) -> some View {
        let days = JournalBrowser.days(JournalBrowser.filtered(journal.cards, JournalFilter(coin: filter.coin, sleeve: filter.sleeve, kind: filter.kind, book: filter.book)))
        return countTable(columns: ["日期", "动作", "决策轮次", "币数"] + JournalAction.kindOrder.map { JournalAction.title($0) },
                          empty: days.isEmpty) {
            ForEach(days) { day in
                GridRow {
                    Text(Self.dayTitle(day.dayStart)).fontWeight(.medium)
                    Text("\(day.total)")
                    Text("\(day.rounds)")
                    Text("\(day.coins)")
                    ForEach(JournalAction.kindOrder, id: \.self) { Text(count(day.kinds.count($0))) }
                }
                .contentShape(Rectangle())
                .onTapGesture { showDay(day.dayStart) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { showDay(day.dayStart) }
            }
        }
    }

    private func coinTable(_ journal: TradeJournal) -> some View {
        let coins = JournalBrowser.coinSummaries(JournalBrowser.filtered(journal.cards, JournalFilter(sleeve: filter.sleeve, kind: filter.kind, day: filter.day, book: filter.book)))
        return countTable(columns: ["币种", "动作"] + JournalAction.kindOrder.map { JournalAction.title($0) } + ["最近一次", "当时目标仓位"],
                          empty: coins.isEmpty) {
            ForEach(coins) { coin in
                GridRow {
                    Text(coin.coin).fontWeight(.medium)
                    Text("\(coin.total)")
                    ForEach(JournalAction.kindOrder, id: \.self) { Text(count(coin.kinds.count($0))) }
                    Text(coin.latest.map(LiveFormat.time) ?? "—").foregroundStyle(.secondary)
                    Text(JournalFormat.weight(coin.latestWeight))
                }
                .contentShape(Rectangle())
                .onTapGesture { showCoin(coin.coin) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { showCoin(coin.coin) }
            }
        }
    }

    private func countTable<Rows: View>(columns: [String], empty: Bool, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if empty {
                placeholder("没有符合筛选的卡", nil)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 26, verticalSpacing: 9) {
                    GridRow {
                        ForEach(columns, id: \.self) { Text($0) }
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    Divider()
                    rows()
                }
                .font(.system(size: 12)).monospacedDigit()
                Text("点一行，在列表里只看这一天（这个币）的卡。").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesktopTheme.card, in: DesktopTheme.surfaceShape)
        .overlay { DesktopTheme.surfaceShape.strokeBorder(DesktopTheme.border, lineWidth: 1) }
    }

    private func showDay(_ day: Double) {
        filter.day = day
        mode = .list
    }

    private func showCoin(_ coin: String) {
        filter.coin = coin
        mode = .list
    }

    private func count(_ value: Int) -> String { value == 0 ? "—" : "\(value)" }

    private static func dayTitle(_ dayStart: Double) -> String {
        Date(milliseconds: dayStart).formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated).locale(Locale(identifier: "zh_CN")))
    }

    private func placeholder(_ title: String, _ detail: String?) -> some View {
        let loading = store.state.isLoading && store.journal == nil
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            if loading { ProgressView().controlSize(.small) } else { Image(systemName: "text.document").foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .medium))
                if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(.secondary) }
            }
            if store.state.canRetry, store.journal == nil {
                Button("重试") { Task { await store.load(force: true) } }.controlSize(.small)
            }
        }
    }
}

/// One card in the list: kind, coin, marks, weight change and the summary on one line.
private struct JournalRow: View {
    let card: JournalCard
    let selected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(card.action?.title ?? JournalAction.title(nil)).font(.system(size: 12, weight: .semibold))
                .frame(width: 38, alignment: .leading)
            Text(card.base ?? card.coin ?? "—").font(.system(size: 12, weight: .medium)).lineLimit(1)
                .frame(minWidth: 40, idealWidth: 70, maxWidth: 70, alignment: .leading)
            if let action = card.action, action.w_before != nil || action.w_after != nil {
                // Gives way first when the list pane is narrow.
                ViewThatFits(in: .horizontal) {
                    Text(JournalFormat.weight(action.w_before) + " → " + JournalFormat.weight(action.w_after))
                        .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                    Color.clear.frame(width: 0)
                }
            }
            Text(card.summary_zh ?? "").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 6)
            if card.placeholder { ReasonBadge(text: "演练", tint: DesktopTheme.orange) }
            if card.sealed == true { ReasonBadge(text: "封存期", tint: .secondary) }
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(selected ? Color.accentColor.opacity(0.12) : .clear)
    }
}

/// The selected card in full: what, when, which book, then ReasonCardDetail (weights, chain, factors, sleeves,
/// ranks, note) under the one-sentence summary.
private struct JournalCardPane: View {
    let card: JournalCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text((card.base ?? card.coin ?? "—") + " · " + (card.action?.title ?? JournalAction.title(nil)))
                    .font(.system(size: 16, weight: .semibold))
                if card.placeholder { ReasonBadge(text: "演练", tint: DesktopTheme.orange) }
                if card.sealed == true { ReasonBadge(text: "封存期", tint: .secondary) }
            }
            Text("决策时间 " + (card.tauMs.map(LiveFormat.time) ?? card.tau ?? "—"))
                .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            if let summary = card.summary_zh, !summary.isEmpty {
                Text(summary).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            ReasonCardDetail(card: card)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
