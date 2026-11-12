import Foundation
import Testing
@testable import PortSightKit

/// GET /ibkr/activity and /ibkr/heartbeat: decoding, de-duplication, order histories, cash, and how the store pages.
@MainActor
struct IBKRActivityTests {
    private let base = "https://chrismac-mini.tail99a219.ts.net"

    private let firstPage = #"""
    {"items": [
      {"seq": 3, "id": "f1", "kind": "fill", "at": "2026-11-10T15:31:00Z", "source": "flex", "symbol": "AAPL", "sec_type": "STK",
       "side": "BUY", "quantity": 10, "price": "225.5", "commission": -1, "commission_currency": "USD", "currency": "USD",
       "exec_id": "e1", "perm_id": 991},
      {"seq": 1, "id": "o1", "kind": "order", "at": "2026-11-10T15:30:00Z", "source": "flex", "status": "submitted", "symbol": "AAPL",
       "side": "BUY", "order_type": "LMT", "limit_price": 226, "quantity": 10, "filled": 0, "remaining": 10, "perm_id": 991},
      {"seq": 2, "id": "o2", "kind": "order", "at": "2026-11-10T15:31:00Z", "source": "flex", "status": "filled", "symbol": "AAPL",
       "side": "BUY", "order_type": "LMT", "limit_price": 226, "quantity": 10, "filled": 10, "remaining": 0, "perm_id": 991},
      {"seq": 9, "id": "c1", "kind": "cash", "at": "2026-06-05T00:00:00Z", "source": "flex", "type": "deposit", "amount": 5000,
       "currency": "USD", "description": "银行入金"},
      {"seq": 10, "id": "c2", "kind": "cash", "at": "2026-09-01T00:00:00Z", "source": "flex", "type": "dividend", "amount": 12.5,
       "currency": "USD", "symbol": "SPY"},
      {"seq": 11, "id": "c3", "kind": "cash", "at": "2026-09-02T00:00:00Z", "source": "flex", "type": "withdrawal", "amount": -800},
      {"no_id": true}, null
    ], "next_cursor": "c-11", "before": "b-1", "has_more": false}
    """#

    // MARK: Decoding and lists

    @Test func pagesDecodeLeniently() throws {
        let page = try JSONDecoder().decode(IBKRActivityPage.self, from: Data(firstPage.utf8))
        #expect(page.items.count == 6 && page.next_cursor == "c-11" && page.before == "b-1" && page.has_more == false)
        let fill = try #require(page.items.first { $0.id == "f1" })
        #expect(fill.kind == .fill && fill.price == 225.5 && fill.perm_id == "991" && fill.isBuy)
        #expect(fill.title == "买入 AAPL" && fill.detail == "10 股 × $225.50 · 佣金 $1.00")
        #expect(fill.signedValue == -2255)

        // Another list key, numbers as cursors, an unknown kind.
        let other = try JSONDecoder().decode(IBKRActivityPage.self, from: Data(#"{"activities": [{"id": 7, "kind": "weird"}], "next_cursor": 42, "before": null}"#.utf8))
        #expect(other.items.first?.id == "7" && other.items.first?.kind == .other && other.next_cursor == "42" && other.before == nil)
        #expect(try JSONDecoder().decode(IBKRHeartbeat.self, from: Data(#"{"activity_seq": "118"}"#.utf8)).activity_seq == 118)
    }

    @Test func listsAreByTimeAndShowAnOrderOnce() throws {
        var items = try JSONDecoder().decode(IBKRActivityPage.self, from: Data(firstPage.utf8)).items
        // The same filled order again from the realtime feed (another id, same perm_id and status): shown once,
        // the realtime one kept. The same id twice is one row too.
        items.append(IBKRActivity(id: "o2-rt", kind: .order, at: "2026-11-10T15:31:01Z", source: "realtime", seq: 120,
                                  symbol: "AAPL", side: "BUY", quantity: 10, perm_id: "991", status: "filled"))
        items.append(items[0])
        let visible = IBKRActivityList.visible(items)
        #expect(visible.filter { $0.kind == .order && $0.status == "filled" }.map(\.id) == ["o2-rt"])
        #expect(visible.filter { $0.id == "f1" }.count == 1)
        // By time (not by seq): newest first.
        #expect(visible.map(\.id) == ["o2-rt", "f1", "o1", "c3", "c2", "c1"])

        let trades = IBKRActivityList.trades(items, symbol: "aapl")
        #expect(trades.allSatisfy { $0.kind == .fill || $0.kind == .order } && trades.count == 3)
        #expect(IBKRActivityList.symbols(items) == ["AAPL"])

        let order = try #require(IBKRActivityList.order("991", in: items))
        #expect(order.steps.map(\.status) == ["submitted", "filled"] && order.fills.map(\.id) == ["f1"])
        #expect(!order.isOpen && order.averagePrice == 225.5 && order.quantity == 10)
        let row = try #require(order.asPortfolioOrder)
        #expect(row.side == .buy && row.status == .completed && row.orderStateText == "已成交" && row.price == 225.5)
    }

    @Test func cashIsSummedByType() throws {
        let items = try JSONDecoder().decode(IBKRActivityPage.self, from: Data(firstPage.utf8)).items
        let totals = IBKRActivityList.cashTotals(items)
        #expect(totals[.deposit] == 5000 && totals[.dividend] == 12.5 && totals[.withdrawal] == -800)
        #expect(IBKRActivityList.cash(items, type: .dividend).map(\.id) == ["c2"])
        let dividend = try #require(items.first { $0.id == "c2" })
        #expect(dividend.title == "分红 · SPY" && dividend.asDemoActivity.amount == 12.5 && dividend.asDemoActivity.category == "分红")
    }

    @Test func daysGroupInLocalTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let items = [
            IBKRActivity(id: "a", kind: .fill, at: "2026-11-10T14:00:00Z"),  // 11 Nov 01:00 in Sydney
            IBKRActivity(id: "b", kind: .fill, at: "2026-11-10T12:00:00Z"),  // 10 Nov 23:00
            IBKRActivity(id: "c", kind: .fill, at: "2026-11-10T11:00:00Z"),
        ]
        let groups = IBKRActivityList.byDay(items, calendar: calendar)
        #expect(groups.map { $0.items.map(\.id) } == [["a"], ["b", "c"]])
        let now = ISO8601DateFormatter().date(from: "2026-11-11T02:00:00Z")!
        #expect(IBKRActivityList.dayTitle(groups[0].day, now: now, calendar: calendar) == "今天")
        #expect(IBKRActivityList.dayTitle(groups[1].day, now: now, calendar: calendar) == "昨天")
    }

    // MARK: Store

    private final class FakeRelay {
        var answers: [String: Result<Data, Error>] = [:]
        var reads: [(RelayEndpoint, [URLQueryItem])] = []

        func read(_ endpoint: RelayEndpoint, _ query: [URLQueryItem]) async throws -> Data {
            reads.append((endpoint, query))
            let key = endpoint.rawValue + (query.isEmpty ? "" : "?" + query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&"))
            guard let answer = answers[key] else { throw ServerError.http(500) }
            return try answer.get()
        }

        func answer(_ key: String, _ json: String) { answers[key] = .success(Data(json.utf8)) }
    }

    private func store(_ relay: FakeRelay, cache: String? = nil) -> IBKRActivityStore {
        IBKRActivityStore(read: { try await relay.read($0, $1) }, base: { self.base }, cacheName: cache, minGap: 3_600)
    }

    @Test func theStorePagesAsTheRelaySays() async throws {
        let relay = FakeRelay()
        relay.answer("/ibkr/activity", firstPage)
        let activity = store(relay)
        await activity.refresh(force: true)
        #expect(activity.phase == .loaded && activity.items.count == 6 && !activity.reachedStart)
        #expect(relay.reads.map(\.0) == [.ibkrActivity] && relay.reads[0].1.isEmpty)

        // Heartbeat: a number not seen yet → only what is new, again while has_more.
        relay.answer("/ibkr/heartbeat", #"{"activity_seq": 13}"#)
        relay.answer("/ibkr/activity?cursor=c-11", #"{"items": [{"id": "f2", "seq": 12, "kind": "fill", "at": "2026-11-11T15:00:00Z", "source": "realtime", "symbol": "TSLA", "side": "SELL", "quantity": 1, "price": 250}], "next_cursor": "c-12", "has_more": true}"#)
        relay.answer("/ibkr/activity?cursor=c-12", #"{"items": [{"id": "p1", "seq": 13, "kind": "position", "at": "2026-11-11T15:00:01Z", "source": "realtime", "symbol": "TSLA", "old_quantity": 5, "new_quantity": 4}], "next_cursor": "c-13", "has_more": false}"#)
        await activity.heartbeat()
        #expect(activity.items.count == 8)
        #expect(activity.visible.first?.id == "p1" && activity.visible.first?.detail == "5 → 4")

        // The same number again: only the heartbeat is read. An automatic refresh within 10 s reads nothing.
        relay.reads = []
        await activity.heartbeat()
        #expect(relay.reads.isEmpty)  // a second poller within 10 s adds nothing
        await activity.heartbeat(force: true)
        #expect(relay.reads.map(\.0) == [.ibkrHeartbeat])
        relay.reads = []
        await activity.refresh()
        #expect(relay.reads.isEmpty)

        // Older pages until `before` is null. A cursor and `before` are never sent together.
        relay.answer("/ibkr/activity?before=b-1", #"{"items": [{"id": "old", "kind": "cash", "at": "2026-06-05T00:00:00Z", "type": "fee", "amount": -10}], "before": null}"#)
        await activity.loadOlder()
        #expect(activity.reachedStart && activity.items.contains { $0.id == "old" })
        #expect(relay.reads.allSatisfy { reading in !(reading.1.contains { $0.name == "cursor" } && reading.1.contains { $0.name == "before" }) })

        // A failed read keeps what is there.
        relay.answers["/ibkr/activity?cursor=c-13"] = .failure(URLError(.notConnectedToInternet))
        await activity.refresh(force: true)
        #expect(activity.items.count == 9 && activity.isSaved)
        #expect(activity.phase == .failed("连不上服务器（检查网络）"))
    }

    @Test func notOpenYetAndKeptBetweenLaunches() async throws {
        let relay = FakeRelay()
        relay.answers["/ibkr/activity"] = .failure(ServerError.http(404))
        let closed = store(relay)
        await closed.refresh(force: true)
        #expect(closed.phase == .notOpen && closed.items.isEmpty)

        let name = "ibkr_activity_test_\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(at: RelayCache.directory.appendingPathComponent(name)) }
        relay.answer("/ibkr/activity", firstPage)
        let first = store(relay, cache: name)
        await first.refresh(force: true)
        let again = store(relay, cache: name)
        #expect(again.items.count == 6 && again.isSaved && again.phase == .loaded)
        // It continues from the saved cursor.
        relay.reads = []
        relay.answer("/ibkr/activity?cursor=c-11", #"{"items": [], "next_cursor": "c-11", "has_more": false}"#)
        await again.refresh(force: true)
        #expect(relay.reads.first?.1.first?.name == "cursor" && !again.isSaved)
    }

    @Test func theTimelineFoldsAnOrderIntoOneLine() throws {
        let items = try JSONDecoder().decode(IBKRActivityPage.self, from: Data(firstPage.utf8)).items
            + [IBKRActivity(id: "lone", kind: .fill, at: "2026-11-09T15:00:00Z", symbol: "MSFT", side: "SELL", quantity: 2, price: 400)]
        let all = IBKRActivityList.timeline(items)
        // AAPL's two status changes and its fill are one line; a fill without a known order stays on its own.
        #expect(all.map(\.id) == ["order:991", "lone", "c3", "c2", "c1"])
        guard case .order(let order) = all[0] else { Issue.record("not an order"); return }
        #expect(order.title == "买入 AAPL" && order.detail == "已成交 · 10 股 · 均价 $225.50")
        #expect(all[0].asDemoActivity.amount == -2255 && all[0].asDemoActivity.category == "成交")

        #expect(IBKRActivityList.timeline(items, filter: .cash).map(\.id) == ["c3", "c2", "c1"])
        #expect(IBKRActivityList.timeline(items, filter: .trades, search: "msft").map(\.id) == ["lone"])
        #expect(IBKRActivityList.timeline(items, search: "入金").map(\.id) == ["c1"])

        let currencies = IBKRActivityList.cashTotalsByCurrency(items + [IBKRActivity(id: "hk", kind: .cash, currency: "HKD", type: "dividend", amount: 30)])
        #expect(currencies.map(\.currency) == ["USD", "HKD"] && currencies[1].totals[.dividend] == 30 && currencies[0].totals[.dividend] == 12.5)
    }

    @Test func unitsFollowTheInstrument() {
        let fx = IBKRActivity(id: "fx", kind: .fill, symbol: "AUD.USD", side: "SELL", quantity: 4.8906, price: 0.7, sec_type: "CASH")
        #expect(fx.detail == "4.8906 × $0.70")
        let option = IBKRActivity(id: "o", kind: .fill, symbol: "AAPL 250117C200", side: "BUY", quantity: 2, price: 3.5, sec_type: "OPT")
        #expect(option.detail == "2 张 × $3.50")
        #expect(IBKRActivity(id: "s", kind: .fill, quantity: 10, price: 1, sec_type: nil).detail == "10 股 × $1.00")
    }

    @Test func aCancelledReadIsNotAFailure() async throws {
        let relay = FakeRelay()
        relay.answer("/ibkr/activity", firstPage)
        let activity = store(relay)
        await activity.refresh(force: true)
        relay.answers["/ibkr/activity?cursor=c-11"] = .failure(URLError(.cancelled))
        await activity.refresh(force: true)
        #expect(activity.phase == .loaded && !activity.isSaved && activity.items.count == 6)

        // The same for the other relay documents (a pull-to-refresh SwiftUI ended early).
        var calls = 0
        let feed = RelayFeedStore<RelayCalendar>(cacheName: nil, minInterval: 300, read: { _, _ in
            calls += 1
            if calls == 1 { return Data(#"{"events": []}"#.utf8) }
            throw CancellationError()
        }, base: { self.base }) { read in .document(try JSONDecoder().decode(RelayCalendar.self, from: try await read(.calendar, []))) }
        await feed.load(force: true)
        await feed.load(force: true)
        #expect(feed.phase == .loaded && !feed.isSaved)
        // Not held back by minInterval after a cancelled read.
        await feed.load()
        #expect(calls == 3)
        #expect(RelayAPI.isCancellation(URLError(.cancelled)) && !RelayAPI.isCancellation(URLError(.notConnectedToInternet)))
    }

    @Test func withdrawnRecordsAreDeleted() async throws {
        let relay = FakeRelay()
        relay.answer("/ibkr/activity", #"{"items": [{"id": "p1", "kind": "position", "at": "2026-11-12T01:00:00Z", "symbol": "SIDU", "old_quantity": 50443, "new_quantity": 0}, {"id": "act:position:e8397223881dc8c75a2ec7ab", "kind": "position", "at": "2026-11-12T01:00:01Z", "symbol": "SIDU"}, {"id": "f1", "kind": "fill", "at": "2026-11-12T00:00:00Z", "symbol": "SIDU", "side": "BUY", "quantity": 1, "price": 1}], "next_cursor": "c1"}"#)
        let activity = store(relay)
        await activity.refresh(force: true)
        // A record the relay withdrew before it could flag it is never kept.
        #expect(activity.items.map(\.id).sorted() == ["f1", "p1"])
        relay.answer("/ibkr/activity?cursor=c1", #"{"items": [{"id": "p1", "kind": "position", "void": true, "void_reason": "gateway 重连时账户未加载完"}], "next_cursor": "c2"}"#)
        await activity.refresh(force: true)
        #expect(activity.items.map(\.id) == ["f1"] && activity.visible.map(\.id) == ["f1"])
    }
}
