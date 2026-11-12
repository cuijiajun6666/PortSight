import Foundation
import Testing
@testable import PortSightKit

/// The portfolio once paired: the personal IBKR account stands in for the built-in holdings; the quant account,
/// history, activity and orders are empty (尚未接入) instead of built-in figures.
@MainActor
struct LivePortfolioTests {
    private let account = PersonalIBKR(
        as_of: "2026-11-11T08:00:05Z", account: "****4567", netValue: 30_000, cash: 5_000, buyingPower: 20_000,
        positions: [
            IBKRPosition(symbol: "AAPL", conID: 265598, secType: "STK", quantity: 10, cost: 180, marketValue: 2_250,
                         unrealizedPnl: 450, dailyPnl: 50),
            IBKRPosition(symbol: "QQQ", conID: 320227571, secType: "STK", quantity: 40, cost: 450, marketValue: 20_000,
                         unrealizedPnl: 2_000, dailyPnl: -400),
            IBKRPosition(symbol: "TSLA", secType: "STK", quantity: -5, cost: 300, marketValue: -1_250,
                         unrealizedPnl: 250, dailyPnl: nil),
            IBKRPosition(symbol: "USD", secType: "CASH", quantity: 5_000, marketValue: 5_000, unrealizedPnl: 0),
            IBKRPosition(symbol: "MSFT", secType: "STK", quantity: 0, cost: 400, marketValue: 0),
        ])

    @Test func positionsBecomeHoldings() throws {
        let holdings = LivePortfolio.holdings(account)
        // CASH and closed (quantity 0) positions are not holdings; largest value first.
        #expect(holdings.map(\.symbol) == ["QQQ", "AAPL", "TSLA"])
        #expect(holdings.allSatisfy { $0.owner == .personal })

        let aapl = try #require(holdings.first { $0.symbol == "AAPL" })
        #expect(aapl.kind == "股票" && aapl.quantity == 10 && aapl.cost == 180)
        #expect(abs(aapl.price - 225) < 1e-9)
        // Yesterday's close from today's P&L: (2250 - 50) / 10.
        #expect(abs(aapl.previous - 220) < 1e-9)
        #expect(abs(aapl.dayPnL - 50) < 1e-9)

        let qqq = try #require(holdings.first { $0.symbol == "QQQ" })
        #expect(qqq.kind == "ETF" && abs(qqq.previous - 510) < 1e-9 && abs(qqq.dayPnL + 400) < 1e-9)

        // No daily_pnl: it did not move today. A short position keeps its sign.
        let tsla = try #require(holdings.first { $0.symbol == "TSLA" })
        #expect(tsla.quantity == -5 && abs(tsla.price - 250) < 1e-9 && tsla.previous == tsla.price && tsla.dayPnL == 0)
    }

    @Test func kindsFollowSecType() {
        #expect(LivePortfolio.kind("OPT", symbol: "AAPL") == "期权")
        #expect(LivePortfolio.kind("fut", symbol: "ES") == "期货")
        #expect(LivePortfolio.kind("CRYPTO", symbol: "BTC") == "加密货币")
        #expect(LivePortfolio.kind("STK", symbol: "spy") == "ETF")
        #expect(LivePortfolio.kind(nil, symbol: "NVDA") == "股票")
    }

    @Test func figuresComeFromTheAccount() {
        #expect(LivePortfolio.total(.personal, account: account) == 30_000)
        #expect(LivePortfolio.total(.all, account: account) == 30_000)
        #expect(LivePortfolio.cash(.all, account: account) == 5_000)
        // Unrealized P&L of the positions, CASH left out.
        #expect(LivePortfolio.pnl(.personal, account: account) == 2_700)
        #expect(LivePortfolio.dayPnL(.all, account: account) == -350)

        // Without net liquidation: cash plus positions.
        var partial = account
        partial.netValue = nil
        #expect(LivePortfolio.total(.personal, account: partial) == 5_000 + 2_250 + 20_000 - 1_250)
    }

    @Test func theQuantAccountIsEmptyUntilTheRelayHasIt() {
        #expect(LivePortfolio.lots(.quant, account: account).isEmpty)
        #expect(LivePortfolio.total(.quant, account: account) == 0)
        #expect(LivePortfolio.cash(.quant, account: account) == 0)
        #expect(LivePortfolio.pnl(.quant, account: account) == 0)
        #expect(LivePortfolio.dayPnL(.quant, account: account) == 0)
        #expect(LivePortfolio.note(.quant, store: IBKRStore(cache: false)) == nil)
    }

    @Test func nothingReadYetIsEmptyNotBuiltIn() {
        #expect(LivePortfolio.holdings(nil).isEmpty)
        #expect(LivePortfolio.total(.all, account: nil) == 0)
        #expect(LivePortfolio.pnl(.all, account: nil) == 0)
        #expect(LivePortfolio.dayPnL(.all, account: nil) == 0)
    }

    @Test func onlyANotLiveReadNeedsANote() async {
        let base = "https://chrismac-mini.tail99a219.ts.net"
        let json = #"{"available": false, "personal_ibkr": {"available": true, "source": "realtime", "stale": false, "net_liquidation": 30000, "cash": 5000, "positions": []}}"#
        let store = IBKRStore(read: { _, _ in Data(json.utf8) }, base: { base }, post: { (200, Data()) },
                              usesRelay: { true }, cache: false)
        // Built-in figures fill in while nothing is read, and next to the quant account: nothing to say.
        #expect(LivePortfolio.note(.personal, store: store) == nil)
        await store.refreshAccount(force: true)
        #expect(LivePortfolio.note(.personal, store: store) == nil && LivePortfolio.note(.all, store: store) == nil)

        let stale = #"{"personal_ibkr": {"available": true, "source": "flex", "stale": true, "as_of": "2026-11-10T08:00:00Z", "net_liquidation": 1, "positions": []}}"#
        let flex = IBKRStore(read: { _, _ in Data(stale.utf8) }, base: { base }, post: { (200, Data()) }, usesRelay: { true }, cache: false)
        await flex.refreshAccount(force: true)
        #expect(LivePortfolio.note(.personal, store: flex)?.hasPrefix("非实时") == true)
    }

    @Test func builtInHoldingsFillInWhatTheAccountLacks() {
        let real = LivePortfolio.holdings(account)  // QQQ (ETF), AAPL and TSLA (stocks)
        let fillers = LivePortfolio.fillers(real: real)
        // Stocks not held for real (NVDA), crypto since there is none; AAPL is real, and QQQ is an ETF already.
        #expect(fillers.map(\.symbol) == ["NVDA", "BTC", "ETH"])
        #expect(fillers.allSatisfy { $0.owner == .personal })

        // No ETF held: one is added.
        let stocksOnly = real.filter { $0.kind != "ETF" }
        #expect(LivePortfolio.fillers(real: stocksOnly).map(\.symbol).contains("VOO"))
        #expect(LivePortfolio.fillers(real: []).map(\.symbol) == ["NVDA", "AAPL", "BTC", "ETH", "VOO"])
    }

    @Test func theMarketSessionFollowsTheNewYorkClock() {
        func at(_ iso: String) -> MarketSession {
            MarketClock.session(at: ISO8601DateFormatter().date(from: iso)!).session
        }
        #expect(at("2026-11-11T12:00:00Z") == .pre)        // Wed 07:00 New York
        #expect(at("2026-11-11T15:00:00Z") == .regular)    // 10:00
        #expect(at("2026-11-11T22:00:00Z") == .after)      // 17:00
        #expect(at("2026-11-12T02:00:00Z") == .overnight)  // Wed 21:00, Thursday trades
        #expect(at("2026-11-14T02:00:00Z") == .closed)     // Fri 21:00, Saturday does not
        #expect(at("2026-11-14T15:00:00Z") == .closed)     // Saturday
        #expect(at("2026-11-26T15:00:00Z") == .closed)     // Thanksgiving
        #expect(at("2026-11-27T19:00:00Z") == .after)      // 14:00 on an early-close day
        #expect(MarketClock.session(at: ISO8601DateFormatter().date(from: "2026-11-11T15:00:00Z")!).title == "盘中")
    }
}
