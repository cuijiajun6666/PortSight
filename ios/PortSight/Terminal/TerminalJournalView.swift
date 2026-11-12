//
//  TerminalJournalView.swift
//  PortSight
//
//  交易 · 理由卡: every G395 理由卡 the v4 shadow wrote in the last 7 days (GET /journal, JournalStore), newest first,
//  like the Mac page. 列表 groups them by decision round; a card opens its full reasons. 按天 and 按币 count the
//  actions, and a tap there filters the list. Filters: 币种, 子策略, 动作. While the relay keeps the journal closed
//  (404) the page says 「交易理由卡尚未开放」. Only counts and the cards' own fields: no result numbers.
//

import SwiftUI
import Combine
import PortSightKit

private enum JournalPageMode: String, CaseIterable, Hashable {
    case list = "列表", days = "按天", coins = "按币"
}

struct TerminalJournalView: View {
    @State private var mode: JournalPageMode = .list
    @State private var filter = JournalFilter()
    /// Pairing, unpairing or pairing again restarts the reading below at once (only this is followed, not every
    /// change of the server store: the page stays alive in the background and must not re-sort 2000 cards).
    @State private var pairing = ServerStore.shared.pairingState

    private var store: JournalStore { .shared }

    var body: some View {
        NavigationStack {
            PortSightList {
                Section {
                    TerminalHero(eyebrow: "交易理由卡", value: heroValue, detail: heroDetail)
                        .terminalHeroRow()
                }
                if let journal = store.journal {
                    notices(journal)
                    Section {
                        Picker("视图", selection: $mode) {
                            ForEach(JournalPageMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        filters(journal)
                    }
                    switch mode {
                    case .list: listSections(journal)
                    case .days: daySection(journal)
                    case .coins: coinSection(journal)
                    }
                } else if let text = store.state.placeholder {
                    Section { placeholder(text.title, text.detail) }
                }
                Section {
                } footer: {
                    Text(JournalFormat.caution)
                }
            }
            .terminalPageList()
            .toolbar { DemoToolbar(showsScope: false) }
            .navigationDestination(for: String.self) { key in
                if let card = store.journal?.cards.first(where: { $0.key == key }) {
                    TerminalJournalCardView(card: card)
                } else {
                    ContentUnavailableView("这张卡已经不在了", systemImage: "questionmark.circle")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .portSightBackdrop()
                }
            }
            .animation(.smooth, value: mode)
            .sensoryFeedback(.selection, trigger: mode)
        }
        .onReceive(ServerStore.shared.$pairingState.removeDuplicates()) { pairing = $0 }
        .task(id: pairing) {
            while !Task.isCancelled {
                await store.load()
                try? await Task.sleep(for: .seconds(JournalStore.freshFor))
            }
        }
    }

    private var heroValue: String {
        if let journal = store.journal { return "\(journal.cards.count) 张" }
        return store.state == .notOpen ? "尚未开放" : "—"
    }

    private var heroDetail: String {
        guard let journal = store.journal else { return "最近 7 天 · 每次真实成交一张" }
        var text = "最近 7 天"
        if let asOf = journal.asOfMilliseconds { text += " · 更新于 " + LiveFormat.time(asOf) }
        return text
    }

    @ViewBuilder
    private func notices(_ journal: TradeJournal) -> some View {
        let sealed = journal.sealed == true || journal.cards.contains { $0.sealed == true }
        let rehearsal = journal.cards.contains(where: \.placeholder)
        let offline = store.offlineNote
        if sealed || rehearsal || journal.isTruncated || offline != nil {
            Section {
                if let offline {
                    Label(offline, systemImage: "wifi.slash").foregroundStyle(.orange)
                }
                if sealed {
                    Label("封存期：卡里没有收益、盈亏和 IC，\(LiveFeed.shadowUnsealDate) 之前不显示任何结果类数字。", systemImage: "lock.fill")
                }
                if rehearsal {
                    Label("标「演练」的卡是占位冻结期的演练数据，不是真实决策。", systemImage: "theatermasks")
                        .foregroundStyle(.orange)
                }
                if let note = journal.truncationNote {
                    Label(note, systemImage: "clock.arrow.circlepath")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Filters

    @ViewBuilder
    private func filters(_ journal: TradeJournal) -> some View {
        let cards = journal.cards
        Picker("币种", selection: $filter.coin) {
            Text("全部").tag(String?.none)
            ForEach(JournalBrowser.coins(in: cards), id: \.coin) { Text("\($0.coin) · \($0.count)").tag(String?.some($0.coin)) }
        }
        Picker("子策略", selection: $filter.sleeve) {
            Text("全部").tag(String?.none)
            ForEach(JournalBrowser.sleeves(in: cards), id: \.name) { Text("\($0.name) · \($0.count)").tag(String?.some($0.name)) }
        }
        Picker("动作", selection: $filter.kind) {
            Text("全部").tag(String?.none)
            ForEach(JournalBrowser.kinds(in: cards), id: \.kind) { Text("\($0.title) · \($0.count)").tag(String?.some($0.kind)) }
        }
        if JournalBrowser.books(in: cards).count > 1 || filter.book != nil {
            Picker("账户", selection: $filter.book) {
                Text("全部").tag(String?.none)
                ForEach(JournalBrowser.books(in: cards), id: \.book) { Text("\($0.book) · \($0.count)").tag(String?.some($0.book)) }
            }
        }
        if let day = filter.day {
            LabeledContent("日期") {
                Button { filter.day = nil } label: {
                    Label(Self.dayTitle(day), systemImage: "xmark.circle.fill")
                }
            }
        }
        if !filter.isEmpty {
            Button("清除筛选", role: .destructive) { filter = JournalFilter() }
        }
    }

    // MARK: 列表

    @ViewBuilder
    private func listSections(_ journal: TradeJournal) -> some View {
        let shown = JournalBrowser.filtered(journal.cards, filter)
        if shown.isEmpty {
            Section { placeholder("没有符合筛选的卡", "换一个筛选，或点 清除筛选。") }
        }
        ForEach(JournalBrowser.rounds(shown)) { round in
            Section {
                ForEach(round.cards, id: \.key) { card in
                    NavigationLink(value: card.key) { JournalCardRow(card: card) }
                }
            } header: {
                Text((round.tauMs.map(LiveFormat.time) ?? round.tau ?? "时间不明") + " · \(round.coins) 个币")
                    .monospacedDigit()
            } footer: {
                Text(round.kinds.summary).monospacedDigit()
            }
        }
    }

    // MARK: 按天 / 按币

    private func daySection(_ journal: TradeJournal) -> some View {
        let days = JournalBrowser.days(JournalBrowser.filtered(journal.cards, JournalFilter(coin: filter.coin, sleeve: filter.sleeve, kind: filter.kind, book: filter.book)))
        return Section {
            if days.isEmpty { placeholder("没有符合筛选的卡", nil) }
            ForEach(days) { day in
                Button {
                    filter.day = day.dayStart
                    mode = .list
                } label: {
                    countRow(title: Self.dayTitle(day.dayStart), total: day.total,
                             detail: "\(day.rounds) 轮决策 · \(day.coins) 个币", kinds: day.kinds)
                }
                .tint(.primary)
            }
        } footer: {
            Text("点一天，在列表里只看这一天的卡。")
        }
    }

    private func coinSection(_ journal: TradeJournal) -> some View {
        let coins = JournalBrowser.coinSummaries(JournalBrowser.filtered(journal.cards, JournalFilter(sleeve: filter.sleeve, kind: filter.kind, day: filter.day, book: filter.book)))
        return Section {
            if coins.isEmpty { placeholder("没有符合筛选的卡", nil) }
            ForEach(coins) { coin in
                Button {
                    filter.coin = coin.coin
                    mode = .list
                } label: {
                    countRow(title: coin.coin, total: coin.total,
                             detail: "最近 " + (coin.latest.map(LiveFormat.time) ?? "—") + " · 目标仓位 " + JournalFormat.weight(coin.latestWeight),
                             kinds: coin.kinds)
                }
                .tint(.primary)
            }
        } footer: {
            Text("点一个币，在列表里只看它的卡。")
        }
    }

    private func countRow(title: String, total: Int, detail: String, kinds: JournalKindCounts) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(total) 张").font(.subheadline).monospacedDigit()
            }
            Text(kinds.summary).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private static func dayTitle(_ dayStart: Double) -> String {
        Date(milliseconds: dayStart).formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated).locale(Locale(identifier: "zh_CN")))
    }

    private func placeholder(_ title: String, _ detail: String?) -> some View {
        let loading = store.state.isLoading && store.journal == nil
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            if loading { ProgressView().controlSize(.small) } else { Image(systemName: "text.document").foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            if store.state.canRetry, store.journal == nil {
                Button("重试") { Task { await store.load(force: true) } }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One card in the list: kind, coin, marks, weight change and the summary (two lines).
private struct JournalCardRow: View {
    let card: JournalCard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(card.base ?? card.coin ?? "—").font(.subheadline.weight(.semibold))
                Text(card.action?.title ?? JournalAction.title(nil)).font(.subheadline)
                if card.placeholder { ReasonBadge(text: "演练", tint: .orange) }
                if card.sealed == true { ReasonBadge(text: "封存期", tint: .secondary) }
                Spacer(minLength: 4)
                if let action = card.action, action.w_before != nil || action.w_after != nil {
                    Text(JournalFormat.weight(action.w_before) + " → " + JournalFormat.weight(action.w_after))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if let summary = card.summary_zh, !summary.isEmpty {
                Text(summary).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One card in full: what, when, which book, the summary, then TradeReasonCardDetail.
struct TerminalJournalCardView: View {
    let card: JournalCard

    var body: some View {
        PortSightList {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if card.placeholder { ReasonBadge(text: "演练", tint: .orange) }
                        if card.sealed == true { ReasonBadge(text: "封存期", tint: .secondary) }
                    }
                    Text("决策时间 " + (card.tauMs.map(LiveFormat.time) ?? card.tau ?? "—"))
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    if let summary = card.summary_zh, !summary.isEmpty {
                        Text(summary).font(.body)
                    }
                }
                .padding(.vertical, 2)
            }
            Section {
                TradeReasonCardDetail(card: card)
            } header: {
                Text("理由")
            } footer: {
                Text(JournalFormat.caution)
            }
        }
        .listStyle(.insetGrouped)
        .portSightBackdrop()
        .navigationTitle((card.base ?? card.coin ?? "—") + " · " + (card.action?.title ?? JournalAction.title(nil)))
        .navigationBarTitleDisplayMode(.inline)
    }
}
