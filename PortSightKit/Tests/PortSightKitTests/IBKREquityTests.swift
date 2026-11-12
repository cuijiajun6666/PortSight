import Foundation
import Testing
@testable import PortSightKit

/// GET /ibkr/equity: decoding, the chart points, and how the store reads each range with ETag / 304.
@MainActor
struct IBKREquityTests {
    private let base = "https://chrismac-mini.tail99a219.ts.net"

    private let month = #"""
    {"available": true, "range": "1m", "currency": "USD", "as_of": "2026-11-11T09:00:00Z", "source": "realtime",
     "points": [
       {"t": "2026-10-13T00:00:00Z", "nav": 10000, "pnl_cum": 0, "twr_cum": 0},
       {"t": "2026-10-14T00:00:00Z", "nav": "10500", "pnl_cum": 500, "twr_cum": 0.05},
       {"t": "2026-10-15T00:00:00Z", "nav": 9450, "pnl_cum": -550, "twr_cum": -0.055},
       {"t": "2026-11-11T08:59:00Z", "nav": 11450, "pnl_cum": 450, "twr_cum": 0.045},
       {"t": "bad", "nav": 1}, {"nav": 2}
     ],
     "flows": [{"t": "2026-10-20T00:00:00Z", "amount": 1000, "type": "deposit"},
               {"t": "2026-10-25T00:00:00Z", "amount": "-200", "type": "withdrawal"}, {"amount": 5}],
     "warnings": ["Flex 查询缺 Transfers 段，收益率可能失真", " "]}
    """#

    @Test func aRangeDecodes() throws {
        let equity = try JSONDecoder().decode(IBKREquity.self, from: Data(month.utf8))
        #expect(equity.points.count == 4 && equity.flows.count == 2 && equity.warnings.count == 1)
        #expect(equity.pnl == 450 && equity.twr == 0.045 && equity.lastValue == 11450 && equity.isRealtime)
        #expect(equity.flows.map(\.title) == ["入金", "出金"] && equity.flows[1].amount == -200)

        // As chart points: the value, and the fall from the running high.
        let points = equity.chartPoints
        #expect(points.map(\.equity) == [10000, 10500, 9450, 11450])
        #expect(abs(points[2].drawdown - 0.1) < 1e-9 && points[3].drawdown == 0)
        #expect(abs(equity.maxDrawdown - 0.1) < 1e-9)
        #expect(IBKREquityRange.allCases.map(\.title) == ["1天", "1周", "1月", "今年", "1年", "全部"])
    }

    private final class FakeRelay {
        var answers: [String: Result<RelayConditionalRead, Error>] = [:]
        var reads: [(range: String?, etag: String?)] = []

        func read(_ endpoint: RelayEndpoint, _ query: [URLQueryItem], _ etag: String?) async throws -> RelayConditionalRead {
            let range = query.first { $0.name == "range" }?.value
            reads.append((range, etag))
            guard let answer = answers[range ?? ""] else { throw ServerError.http(500) }
            return try answer.get()
        }
    }

    @Test func eachRangeIsReadWithItsETag() async throws {
        let relay = FakeRelay()
        relay.answers["1m"] = .success(.changed(Data(month.utf8), etag: "\"v1\""))
        // A long gap, so a busy machine cannot make the "within 10 s" check flaky.
        let store = IBKREquityStore(read: { try await relay.read($0, $1, $2) }, base: { self.base }, cacheName: nil,
                                    minGap: 3_600)
        await store.load(.month)
        #expect(store.document(.month)?.points.count == 4 && store.phase(.month) == .loaded)
        #expect(relay.reads.last?.etag == nil)

        // Within 10 s nothing is read; forced, the ETag goes along and a 304 keeps the curve.
        await store.load(.month)
        #expect(relay.reads.count == 1)
        relay.answers["1m"] = .success(.notModified)
        await store.load(.month, force: true)
        #expect(relay.reads.last?.etag == "\"v1\"" && store.document(.month)?.lastValue == 11450 && !store.isSaved(.month))

        // Another range is its own document; available=false is not an error.
        relay.answers["1d"] = .success(.changed(Data(#"{"available": false}"#.utf8), etag: nil))
        await store.load(.day)
        #expect(store.document(.day) == nil && store.phase(.day) == .unavailable("还没有账户走势数据"))

        // A failed read keeps the curve as a saved copy; a 400 says the range is not supported.
        relay.answers["1m"] = .failure(URLError(.notConnectedToInternet))
        await store.load(.month, force: true)
        #expect(store.isSaved(.month) && store.document(.month) != nil)
        relay.answers["ytd"] = .failure(ServerError.http(400))
        await store.load(.ytd)
        #expect(store.phase(.ytd) == .failed("服务器不支持这个区间"))
    }

    @Test func theRealCurveLeadsOnceRead() throws {
        // Before pairing (no relay in tests) the built-in curve is used for every range.
        #expect(!Portfolio.hasRealHistory(.personal))
        #expect(Portfolio.points(.personal).count == DemoPortfolioData.points(.personal).count)
    }
}
