import Foundation
import Testing
@testable import PortSightKit

/// GET /journal (G395 交易理由卡): decoding, matching cards to a trade, and what the app shows around them.
struct JournalTests {
    private let base = "https://chrismac-mini.tail99a219.ts.net"

    /// Three cards in the documented shape (as_of, line, kind, sealed, card_schema, window, counts, cards[]), plus a
    /// repeated id and a card for another coin.
    private let document = #"""
    {
      "as_of": "2026-11-11T08:15:00Z",
      "line": "crypto",
      "kind": "journal",
      "sealed": true,
      "card_schema": "g395.card.v1",
      "window": {"from": "2026-11-04T08:15:00Z", "to": "2026-11-11T08:15:00Z"},
      "counts": {"cards": 3, "open": 1, "bad": "x"},
      "cards": [
        {
          "id": "c1", "tau": "2026-11-10T07:45:00Z", "coin": "BTC", "book": "v4_shadow",
          "placeholder": true, "sealed": true,
          "action": {"kind": "open", "w_before": 0, "w_after": 0.032, "delta": 0.032},
          "chain": {"l2": {"intent": "long"}, "l3": {"tags": ["vol_cap", " "]}, "env": {"clipped": false}},
          "signals": {"scores": [{"name": "mom_20d", "value": 1.84, "rank": 4, "n": 52}]},
          "attribution": {
            "top": [{"name_zh": "动量", "contribution": 0.012}, {"name_zh": "资金费率", "contribution": -0.02}],
            "by_sleeve": [{"name": "趋势", "share": 0.7}, {"name": "均值回归", "share": 0.3}],
            "note": "归因只说明这一单的打分来源"
          },
          "summary_zh": "动量排第 4，开多 3.2%。"
        },
        {
          "id": "c2", "tau": "2026-11-10T10:00:00.250Z", "coin": "BTC", "sealed": true,
          "action": {"kind": "add", "w_before": "0.032", "w_after": 0.05},
          "summary_zh": "加仓"
        },
        {"id": "c1", "tau": "2026-11-10T07:45:00Z", "coin": "BTC", "summary_zh": "重复"},
        {"id": "e1", "tau": 1762761600, "coin": "ETH", "action": {"kind": "close"}}
      ]
    }
    """#

    private func ms(_ iso: String) throws -> Double { try #require(JournalTime.milliseconds(iso)) }

    /// A fresh folder for a store's saved copy, so tests never touch the app's own Application Support.
    static func scratch() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("journal-tests-" + UUID().uuidString, isDirectory: true)
    }

    @Test func decodesTheDocumentedFields() throws {
        let journal = try JSONDecoder().decode(TradeJournal.self, from: Data(document.utf8))
        #expect(journal.kind == "journal" && journal.line == "crypto" && journal.sealed == true)
        #expect(journal.card_schema == "g395.card.v1")
        #expect(journal.counts == ["cards": 3, "open": 1])
        // The repeated id is dropped; newest first.
        #expect(journal.cards.map(\.key) == ["c2", "c1", "e1"])

        let open = try #require(journal.cards.first { $0.id == "c1" })
        #expect(open.placeholder && open.sealed == true && open.book == "v4_shadow")
        #expect(open.summary_zh == "动量排第 4，开多 3.2%。")
        #expect(open.action?.title == "开仓" && open.action?.w_after == 0.032 && open.action?.change == 0.032)
        #expect(open.chain?.l2?.intent == "long" && open.chain?.env?.clipped == false)
        #expect(open.tags == ["vol_cap"])
        #expect(open.signals?.scores.first?.rankText == "4/52")
        // Largest contribution by size first.
        #expect(open.topFactors.map(\.name_zh) == ["资金费率", "动量"])
        #expect(open.attribution?.note == "归因只说明这一单的打分来源")
        #expect(open.attribution?.sleeveFractions.map(\.name) == ["趋势", "均值回归"])
        #expect(open.tauMs == (try ms("2026-11-10T07:45:00Z")))

        // A number sent as text, a missing delta worked out from before and after, fractional seconds.
        let add = try #require(journal.cards.first { $0.id == "c2" })
        #expect(add.action?.w_before == 0.032)
        #expect(abs((add.action?.change ?? 0) - 0.018) < 1e-12)
        #expect(add.tauMs == (try ms("2026-11-10T10:00:00Z")) + 250)
        #expect(add.placeholder == false)

        // Epoch seconds for tau; milliseconds, microseconds and nanoseconds are told apart by size.
        #expect(journal.cards.first { $0.id == "e1" }?.tauMs == 1_762_761_600_000)
        #expect(JournalTime.milliseconds(epoch: 1_762_761_600_000) == 1_762_761_600_000)
        #expect(JournalTime.milliseconds(epoch: 1_762_761_600_000_000) == 1_762_761_600_000)
        #expect(JournalTime.milliseconds(epoch: 1_762_761_600_000_000_000) == 1_762_761_600_000)
    }

    @Test func oddBodiesStillDecode() throws {
        let odd = #"{"cards": [null, 5, {"tau": "2026-11-10 07:45:00", "coin": "sol", "placeholder": 1,"#
            + #" "action": {"kind": "flip", "w_before": -0.02, "w_after": 0.02},"#
            + #" "attribution": {"top": [null, {"name_zh": 3, "contribution": "0.5"}], "by_sleeve": [{"name": "A", "share": 60}, {"name": "B", "share": 40}]},"#
            + #" "chain": {"l3": {"tags": ["x", 2, null]}}}]}"#
        let journal = try JSONDecoder().decode(TradeJournal.self, from: Data(odd.utf8))
        let card = try #require(journal.cards.first { $0.coin == "sol" })
        #expect(card.id == nil && card.key == "sol|2026-11-10 07:45:00|flip")
        #expect(card.placeholder)
        // A time without a zone is UTC.
        #expect(card.tauMs == (try ms("2026-11-10T07:45:00Z")))
        #expect(card.action?.title == "反手" && card.action?.change == 0.04)
        #expect(card.topFactors.count == 1 && card.topFactors.first?.name_zh == "3" && card.topFactors.first?.contribution == 0.5)
        #expect(card.tags == ["x", "2"])
        // A rank out of any sane range is no rank (and never traps).
        let huge = try JSONDecoder().decode(JournalScore.self, from: Data(#"{"name": "x", "rank": 1e20, "n": -3}"#.utf8))
        #expect(huge.rank == nil && huge.n == nil && huge.rankText == "—")
        // Percentages adding up to 100 are read as fractions.
        #expect(card.attribution?.sleeveFractions.map(\.fraction) == [0.6, 0.4])
        // Not an object at all: nothing, but no failure.
        #expect(try JSONDecoder().decode(TradeJournal.self, from: Data("[1, 2]".utf8)).cards.isEmpty)
        #expect(journal.cards.count == 1)
    }

    @Test func coinsAreComparedByBaseAsset() {
        #expect(TradeJournal.base("BTCUSDT") == "BTC")
        #expect(TradeJournal.base("BTC-USDT-SWAP") == "BTC")
        #expect(TradeJournal.base("btc/usdt") == "BTC")
        #expect(TradeJournal.base("BTC") == "BTC")
        #expect(TradeJournal.base("ETHUSDC") == "ETH")
        #expect(TradeJournal.base("USDT") == "USDT")
        // Multiplier contracts keep only the coin; a coin that starts with a digit is left alone.
        #expect(TradeJournal.base("1000PEPEUSDT") == "PEPE")
        #expect(TradeJournal.base("1000000MOG-USDT-SWAP") == "MOG")
        #expect(TradeJournal.base("1INCHUSDT") == "1INCH")
    }

    /// Same coin, decided from up to 30 minutes before the opening fill (opening kinds only) until the close.
    @Test func cardsAreMatchedToATradeByCoinAndTime() throws {
        let entry = try ms("2026-11-10T08:00:00Z"), exit = try ms("2026-11-10T12:00:00Z")
        func card(_ id: String, _ tau: String, _ kind: String, coin: String = "BTC") -> JournalCard {
            JournalCard(id: id, tau: tau, coin: coin, action: JournalAction(kind: kind))
        }
        let journal = TradeJournal(cards: [
            card("early-open", "2026-11-10T07:20:00Z", "open"),          // 40 min before: too early
            card("prior-close", "2026-11-10T07:45:00Z", "close"),        // the previous trade's close
            card("open", "2026-11-10T07:45:00Z", "open"),
            card("add", "2026-11-10T09:00:00Z", "add"),
            card("eth", "2026-11-10T09:00:00Z", "add", coin: "ETH"),
            card("close", "2026-11-10T12:01:00Z", "close"),              // within the 2-minute clock allowance
            card("next", "2026-11-10T12:05:00Z", "open"),
        ])
        #expect(journal.cards(symbol: "BTCUSDT", from: entry, to: exit).map(\.key) == ["open", "add", "close"])
        #expect(journal.cards(symbol: "ETH-USDT-SWAP", from: entry, to: exit).map(\.key) == ["eth"])
        #expect(journal.cards(symbol: "SOLUSDT", from: entry, to: exit).isEmpty)
    }

    /// A long trade's cards hold a long before or after; a short's card does not attach to it. No weights: kept.
    @Test func cardsMustAgreeWithTheTradesDirection() throws {
        let entry = try ms("2026-11-10T08:00:00Z"), exit = try ms("2026-11-10T12:00:00Z")
        func card(_ id: String, _ kind: String, _ before: Double?, _ after: Double?) -> JournalCard {
            JournalCard(id: id, tau: "2026-11-10T09:00:00Z", coin: "BTC",
                        action: JournalAction(kind: kind, w_before: before, w_after: after))
        }
        let journal = TradeJournal(cards: [
            card("long-add", "add", 0.02, 0.04),
            card("short-open", "open", 0, -0.03),
            card("long-close", "close", 0.04, 0),
            card("flip-out", "flip", 0.04, -0.02),
            card("no-weights", "add", nil, nil),
        ])
        let long = journal.cards(symbol: "BTCUSDT", side: .long, from: entry, to: exit).map(\.key)
        #expect(Set(long) == ["long-add", "long-close", "flip-out", "no-weights"])
        let short = journal.cards(symbol: "BTCUSDT", side: .short, from: entry, to: exit).map(\.key)
        #expect(Set(short) == ["short-open", "flip-out", "no-weights"])
    }

    /// Around the trade's edges the direction must be the right way round: before the opening fill a card has to
    /// open into the side (not flip out of an earlier trade on it); after the close it has to leave it (not open
    /// the next trade).
    @Test func edgeCardsBelongToTheRightTrade() throws {
        let entry = try ms("2026-11-10T08:00:00Z"), exit = try ms("2026-11-10T12:00:00Z")
        func card(_ id: String, _ tau: String, _ kind: String, _ before: Double, _ after: Double) -> JournalCard {
            JournalCard(id: id, tau: tau, coin: "BTC", action: JournalAction(kind: kind, w_before: before, w_after: after))
        }
        let journal = TradeJournal(cards: [
            card("flip-out-of-long", "2026-11-10T07:40:00Z", "flip", 0.04, -0.03),
            card("flip-into-long", "2026-11-10T07:50:00Z", "flip", -0.03, 0.04),
            card("close", "2026-11-10T12:00:30Z", "close", 0.04, 0),
            card("next-open", "2026-11-10T12:01:00Z", "open", 0, 0.03),
        ])
        #expect(journal.cards(symbol: "BTCUSDT", side: .long, from: entry, to: exit).map(\.key) == ["flip-into-long", "close"])
    }

    /// At the 2000-card cap the cards cover less than the 7-day window: the oldest card sent is where they start.
    @Test func aCutDocumentCoversOnlyFromItsOldestCard() throws {
        let cards = (0..<TradeJournal.maxCards).map { index in
            JournalCard(id: "c\(index)", tau: String(1_794_200_000 + index * 60), coin: "BTC")
        }
        let full = TradeJournal(as_of: "2026-11-11T00:00:00Z",
                                window: JournalWindow(from: "2026-11-04T00:00:00Z", to: "2026-11-11T00:00:00Z"),
                                cards: cards)
        #expect(full.isTruncated)
        // 2026-11-08, later than window.from (2026-11-04).
        #expect(full.keptSince == 1_794_200_000_000)
        let before = 1_794_200_000_000.0 - 3_600_000
        #expect(full.startsBeforeWindow(before))
        #expect(full.earlierNote(before)?.contains("最近的一部分") == true)
        #expect(full.emptyReason(symbol: "BTCUSDT", start: before).contains("最近的一部分"))

        // counts saying more than were sent also means cut.
        var counted = TradeJournal(cards: Array(cards.prefix(3)))
        counted.counts = ["cards": 10]
        #expect(counted.isTruncated)
        counted.counts = ["cards": 3]
        #expect(!counted.isTruncated)
    }

    /// A long list keeps the first card and the newest ones; the rest is counted by kind.
    @Test func longListsAreCondensed() {
        let kinds = ["open"] + Array(repeating: "add", count: 6) + ["reduce", "reduce", "close"]
        let cards = kinds.enumerated().map { index, kind in
            JournalCard(id: "k\(index)", tau: String(1_762_761_600 + index * 900), coin: "BTC", action: JournalAction(kind: kind))
        }
        let condensed = TradeJournal.condensed(cards, keep: 6)
        #expect(condensed.hidden == 4)
        #expect(condensed.cards.map(\.key) == ["k0", "k5", "k6", "k7", "k8", "k9"])
        #expect(TradeJournal.condensed(Array(cards.prefix(6)), keep: 6).hidden == 0)
        #expect(TradeJournal.kindSummary(cards) == "开仓 1 · 加仓 6 · 减仓 2 · 平仓 1")
    }

    @Test func tradesOlderThanTheWindowSaySo() throws {
        let journal = try JSONDecoder().decode(TradeJournal.self, from: Data(document.utf8))
        #expect(journal.keptSince == (try ms("2026-11-04T08:15:00Z")))
        #expect(journal.startsBeforeWindow(try ms("2026-11-01T00:00:00Z")))
        #expect(!journal.startsBeforeWindow(try ms("2026-11-10T00:00:00Z")))
        #expect(journal.emptyReason(symbol: "SOLUSDT", start: try ms("2026-11-10T00:00:00Z")) == "这段时间没有 SOL 对得上的理由卡。")
        #expect(journal.earlierNote(try ms("2026-11-10T00:00:00Z")) == nil)
        #expect(journal.emptyReason(symbol: "SOLUSDT", start: try ms("2026-11-01T00:00:00Z")).contains("最近 7 天"))
        // Without a window: 7 days before as_of.
        let bare = TradeJournal(as_of: "2026-11-11T00:00:00Z")
        #expect(bare.keptSince == (try ms("2026-11-04T00:00:00Z")))
    }

    @Test func formatting() {
        #expect(JournalFormat.weight(0.032) == "+3.2%")
        #expect(JournalFormat.weight(-0.015) == "−1.5%")
        #expect(JournalFormat.weight(0) == "0%")
        #expect(JournalFormat.weight(nil) == "—")
        #expect(JournalFormat.number(0.0123) == "+0.012")
        #expect(JournalFormat.number(-1.5) == "−1.50")
        #expect(JournalFormat.number(0.00004) == "+4.0e-05")
        #expect(JournalFormat.number(nil) == "—")
        #expect(JournalFormat.share(0.7) == "70%")
        #expect(JournalAction.title("reduce") == "减仓" && JournalAction.title("close") == "平仓")
        #expect(JournalAction.title("rebalance") == "rebalance" && JournalAction.title(nil) == "调仓")
        #expect(JournalScore(name: "x").rankText == "—" && JournalScore(name: "x", rank: 3).rankText == "3")
    }

    /// Same bearer and HTTPS-only rules as the other reads; the line goes in the query.
    @Test func journalRequest() throws {
        let request = try #require(RelayAPI.readRequest(base: base, endpoint: .journal, deviceToken: "dev-token",
                                                        query: [URLQueryItem(name: "line", value: "crypto")]))
        #expect(request.url?.absoluteString == base + "/journal?line=crypto")
        #expect(request.httpMethod == "GET" && request.value(forHTTPHeaderField: "Authorization") == "Bearer dev-token")
        #expect(RelayAPI.readRequest(base: "http://mac-mini.ts.net", endpoint: .journal, deviceToken: "t") == nil)
        #expect(!RelayEndpoint.pending.contains(.journal))
    }

    /// What the store makes of each answer, with the relay read replaced.
    @Test func storeMapsTheRelaysAnswers() async throws {
        var answer: Result<Data, Error> = .failure(ServerError.http(404))
        var reads = 0
        var base: String? = "https://a.ts.net"
        let store = JournalStore(read: { endpoint, query in
            reads += 1
            #expect(endpoint == .journal && query == [URLQueryItem(name: "line", value: "crypto")])
            return try answer.get()
        }, base: { base }, directory: Self.scratch(), restoresSaved: false)

        // 404: the switch is off. Not a failure, no 重试, and not read again within 5 minutes.
        await store.load()
        #expect(store.state == .notOpen && !store.state.canRetry && reads == 1)
        await store.load()
        #expect(reads == 1)

        // 401 (forced read): pair again.
        answer = .failure(ServerError.unauthorized)
        await store.load(force: true)
        #expect(store.state == .needsRepair && reads == 2)

        // Not JSON: a failure that can be retried.
        answer = .success(Data("<html>".utf8))
        await store.load(force: true)
        #expect(store.state.canRetry)

        // Cards, then a failed re-read: the cards stay on screen.
        answer = .success(Data(document.utf8))
        await store.load(force: true)
        #expect(store.journal?.cards.count == 3)
        answer = .failure(URLError(.notConnectedToInternet))
        await store.load(force: true)
        #expect(store.journal?.cards.count == 3)

        // 429: a failure that keeps the cards on screen.
        answer = .success(Data(document.utf8))
        await store.load(force: true)
        answer = .failure(ServerError.rateLimited)
        await store.load(force: true)
        #expect(store.journal?.cards.count == 3)
        #expect(JournalStore.freshFor >= 30)

        // Another relay: read again from scratch; unpaired: nothing.
        answer = .failure(ServerError.http(404))
        base = "https://b.ts.net"
        await store.load()
        #expect(store.state == .notOpen)
        base = nil
        let before = reads
        await store.load()
        #expect(store.state == .unpaired && reads == before)
    }

    /// The relay switched while a read was under way: the old answer is dropped and the new relay is read.
    /// Forgetting the relay shows 未配对, not a spinner for a read that is not happening.
    @Test func aRelaySwitchDuringAReadReadsTheNewOne() async throws {
        var base: String? = "https://a.ts.net"
        var seen: [String] = []
        var release: CheckedContinuation<Void, Never>?
        let answer = Data(document.utf8)
        let store = JournalStore(read: { @MainActor _, _ in
            let asked = base ?? ""
            seen.append(asked)
            if asked == "https://a.ts.net" {
                // Held until the test has switched relays.
                await withCheckedContinuation { release = $0 }
                return answer
            }
            throw ServerError.http(404)
        }, base: { base }, directory: Self.scratch(), restoresSaved: false)
        async let loading: Void = store.load()
        while release == nil { await Task.yield() }
        base = "https://b.ts.net"
        store.reset()
        release?.resume()
        await loading
        #expect(seen == ["https://a.ts.net", "https://b.ts.net"], "seen: \(seen), state: \(store.state)")
        #expect(store.state == .notOpen)

        base = nil
        store.reset()
        #expect(store.state == .unpaired && !store.state.isLoading)
    }

    /// The last good answer survives a relaunch for the same relay; a failed read keeps it on screen and on disk
    /// (with the offline note); a copy saved for another relay is ignored; reset deletes it; a 404 drops it.
    @Test func savedCopyKeepsCardsOffline() async throws {
        let folder = Self.scratch()
        let file = folder.appendingPathComponent("journal_crypto.json")
        var answer: Result<Data, Error> = .success(Data(document.utf8))
        var base: String? = "https://a.ts.net"
        func store() -> JournalStore {
            JournalStore(read: { _, _ in try answer.get() }, base: { base }, directory: folder, restoresSaved: false)
        }

        // A good read is saved.
        let first = store()
        await first.load()
        #expect(first.journal?.cards.count == 3 && FileManager.default.fileExists(atPath: file.path))
        #expect(first.offlineNote == nil)

        // Relaunch offline: the saved cards come back, are not taken as fresh, and stay when the read fails.
        answer = .failure(URLError(.notConnectedToInternet))
        let second = store()
        await second.restoreSaved()
        #expect(second.journal?.cards.count == 3)
        await second.load()
        #expect(second.journal?.cards.count == 3)
        #expect(second.offlineNote?.hasPrefix("离线：显示 ") == true && second.offlineNote?.hasSuffix(" 保存的理由卡") == true)
        // 401 and 429 keep them too.
        answer = .failure(ServerError.unauthorized)
        await second.load(force: true)
        #expect(second.journal?.cards.count == 3)
        answer = .failure(ServerError.rateLimited)
        await second.load(force: true)
        #expect(second.journal?.cards.count == 3 && FileManager.default.fileExists(atPath: file.path))

        // Another relay paired: the copy is not shown.
        base = "https://b.ts.net"
        let other = store()
        await other.restoreSaved()
        #expect(other.journal == nil)

        // Reset (unpair / switch) deletes it.
        base = "https://a.ts.net"
        second.reset()
        #expect(!FileManager.default.fileExists(atPath: file.path))

        // A 404 drops the cards and the copy.
        answer = .success(Data(document.utf8))
        let third = store()
        await third.load()
        #expect(FileManager.default.fileExists(atPath: file.path))
        answer = .failure(ServerError.http(404))
        await third.load(force: true)
        #expect(third.state == .notOpen && !FileManager.default.fileExists(atPath: file.path))
        try? FileManager.default.removeItem(at: folder)
    }

    /// Several cards opening at once share one read.
    @Test func concurrentLoadsShareOneRead() async {
        var reads = 0
        let store = JournalStore(read: { @MainActor _, _ in
            reads += 1
            // Several suspension points, so the second load arrives while this read is under way.
            for _ in 0..<20 { await Task.yield() }
            throw ServerError.http(404)
        }, base: { "https://a.ts.net" }, directory: Self.scratch(), restoresSaved: false)
        async let first: Void = store.load()
        async let second: Void = store.load()
        _ = await (first, second)
        #expect(reads == 1 && store.state == .notOpen)
    }

    /// A 404 (switch off) is "not open yet", never an error.
    @Test func placeholders() {
        #expect(JournalStore.State.notOpen.placeholder?.title == "交易理由卡尚未开放")
        #expect(JournalStore.State.notOpen.canRetry == false)
        #expect(JournalStore.State.failed("x").canRetry)
        #expect(JournalStore.State.loaded(TradeJournal()).placeholder == nil)
        #expect(JournalStore.State.loading.isLoading)
    }
}

/// The 理由卡 page: filters, decision rounds and the per-day / per-coin counts.
struct JournalBrowserTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func card(_ id: String, _ tau: String, _ coin: String, _ kind: String, sleeves: [String] = [],
                      after: Double? = nil) -> JournalCard {
        JournalCard(id: id, tau: tau, coin: coin, action: JournalAction(kind: kind, w_after: after),
                    attribution: JournalAttribution(by_sleeve: sleeves.map { JournalSleeve(name: $0, share: 0.5) }))
    }

    private var cards: [JournalCard] {
        TradeJournal(cards: [
            card("a", "2026-11-10T08:00:00Z", "BTC", "open", sleeves: ["趋势", "套息"], after: 0.03),
            card("b", "2026-11-10T08:00:00Z", "ETH", "add", sleeves: ["趋势"]),
            card("c", "2026-11-10T08:15:00Z", "BTCUSDT", "Close", sleeves: ["套息"], after: 0),
            card("d", "2026-11-11T01:00:00Z", "SOL", "rebalance"),
        ]).cards
    }

    @Test func filters() {
        let all = cards
        #expect(JournalBrowser.filtered(all, JournalFilter(), calendar: utc).count == 4)
        #expect(JournalBrowser.filtered(all, JournalFilter(coin: "BTC"), calendar: utc).map(\.key) == ["c", "a"])
        #expect(Set(JournalBrowser.filtered(all, JournalFilter(sleeve: "趋势"), calendar: utc).map(\.key)) == ["b", "a"])
        #expect(JournalBrowser.filtered(all, JournalFilter(kind: "close"), calendar: utc).map(\.key) == ["c"])
        let day = JournalBrowser.dayStart(JournalTime.milliseconds("2026-11-10T08:00:00Z")!, calendar: utc)
        #expect(JournalBrowser.filtered(all, JournalFilter(day: day), calendar: utc).count == 3)
        #expect(JournalBrowser.filtered(all, JournalFilter(coin: "BTC", kind: "open"), calendar: utc).map(\.key) == ["a"])
        #expect(!JournalFilter(coin: "BTC").isEmpty && JournalFilter().isEmpty)
    }

    @Test func optionsAreCountedAndOrdered() {
        let all = cards
        #expect(JournalBrowser.coins(in: all).map(\.coin) == ["BTC", "ETH", "SOL"])
        #expect(JournalBrowser.coins(in: all).first?.count == 2)
        #expect(JournalBrowser.sleeves(in: all).map(\.name) == ["套息", "趋势"] && JournalBrowser.sleeves(in: all).map(\.count) == [2, 2])
        // A card without an action counts as 调仓 and the 调仓 filter finds it.
        let bare = all + [JournalCard(id: "e", tau: "2026-11-10T09:00:00Z", coin: "BTC")]
        #expect(JournalBrowser.kinds(in: bare).contains { $0.kind == "" && $0.title == "调仓" && $0.count == 1 })
        #expect(JournalBrowser.filtered(bare, JournalFilter(kind: ""), calendar: utc).map(\.key) == ["e"])
        #expect(JournalBrowser.kinds(in: all).map(\.kind) == ["open", "add", "close", "rebalance"])
        #expect(JournalBrowser.kinds(in: all).map(\.title) == ["开仓", "加仓", "平仓", "rebalance"])
    }

    @Test func roundsGroupOneDecisionTime() {
        let rounds = JournalBrowser.rounds(cards)
        #expect(rounds.count == 3)
        #expect(rounds.first?.cards.map(\.key) == ["d"])
        let eight = rounds.last
        #expect(eight?.cards.map(\.key) == ["a", "b"] && eight?.coins == 2)
        #expect(eight?.kinds.summary == "开仓 1 · 加仓 1")
    }

    @Test func dayAndCoinSummaries() {
        let days = JournalBrowser.days(cards, calendar: utc)
        #expect(days.map(\.total) == [1, 3])
        #expect(days.last?.rounds == 2 && days.last?.coins == 2)
        #expect(days.last?.kinds.count("open") == 1 && days.last?.kinds.count("close") == 1)
        let coins = JournalBrowser.coinSummaries(cards)
        #expect(coins.map(\.coin) == ["BTC", "ETH", "SOL"])
        #expect(coins.first?.total == 2 && coins.first?.latestWeight == 0)
        #expect(coins.first?.latest == JournalTime.milliseconds("2026-11-10T08:15:00Z"))
    }
}

/// The 11-11 additions: trade_id / model / order_ids on cards; truncated / covered_from / total_available / limit.
struct JournalLinkTests {
    private func ms(_ iso: String) throws -> Double { try #require(JournalTime.milliseconds(iso)) }

    @Test func decodesTheNewFields() throws {
        let json = #"""
        {"truncated": "true", "covered_from": "2026-11-09T00:00:00Z", "total_available": 5400, "limit": 2000,
         "cards": [{"id": "x", "tau": "2026-11-10T08:00:00Z", "coin": "BTC", "book": "paper-1",
                    "trade_id": "G263-BTC0019", "model": "v4 G263", "order_ids": ["o1", 2, null]}]}
        """#
        let journal = try JSONDecoder().decode(TradeJournal.self, from: Data(json.utf8))
        let card = try #require(journal.cards.first)
        #expect(card.trade_id == "G263-BTC0019" && card.model == "v4 G263" && card.order_ids == ["o1", "2"])
        #expect(journal.truncated == true && journal.total_available == 5400 && journal.limit == 2000)
        #expect(journal.isTruncated)
        #expect(journal.keptSince == (try ms("2026-11-09T00:00:00Z")))
        #expect(journal.truncationNote?.contains("5400") == true)
    }

    @Test func truncationPrefersTheRelaysWord() {
        var journal = TradeJournal(cards: [JournalCard(id: "a", tau: "2026-11-10T08:00:00Z", coin: "BTC")])
        journal.counts = ["cards": 10]
        journal.truncated = false
        #expect(!journal.isTruncated && journal.truncationNote == nil)
        journal.truncated = nil
        journal.total_available = 1
        #expect(!journal.isTruncated)
        journal.total_available = 3
        #expect(journal.isTruncated)
        journal.total_available = nil
        journal.limit = 1
        #expect(journal.isTruncated)
    }

    /// A trade's own cards (trade_id) win; another trade's cards never attach; cards without a trade_id fall back
    /// to coin, direction and time.
    @Test func tradeIDMatchesExactly() throws {
        let entry = try ms("2026-11-10T08:00:00Z"), exit = try ms("2026-11-10T12:00:00Z")
        func card(_ id: String, _ tau: String, trade: String?) -> JournalCard {
            JournalCard(id: id, tau: tau, coin: "BTC", action: JournalAction(kind: "add", w_before: 0.01, w_after: 0.02),
                        trade_id: trade)
        }
        let journal = TradeJournal(cards: [
            card("mine", "2026-11-10T09:00:00Z", trade: "T1"),
            card("mine-late", "2026-11-11T09:00:00Z", trade: "T1"),
            card("other", "2026-11-10T10:00:00Z", trade: "T2"),
            card("loose", "2026-11-10T11:00:00Z", trade: nil),
        ])
        #expect(journal.cards(symbol: "BTCUSDT", side: .long, tradeID: "T1", from: entry, to: exit).map(\.key) == ["mine", "mine-late"])
        #expect(journal.cards(symbol: "BTCUSDT", side: .long, tradeID: "T9", from: entry, to: exit).map(\.key) == ["loose"])
        #expect(journal.cards(symbol: "BTCUSDT", side: .long, from: entry, to: exit).map(\.key) == ["loose"])
    }

    @Test func bookFilter() {
        let cards = [JournalCard(id: "a", tau: "2026-11-10T08:00:00Z", coin: "BTC", book: "paper-1"),
                     JournalCard(id: "b", tau: "2026-11-10T08:00:00Z", coin: "BTC", book: "live-1")]
        #expect(JournalBrowser.filtered(cards, JournalFilter(book: "live-1")).map(\.key) == ["b"])
        #expect(JournalBrowser.books(in: cards).count == 2)
    }
}
