import Foundation
import Testing
@testable import PortsightMac
import PortSightKit

@MainActor
struct PortsightMacTests {
    @Test func scopesReconcileWithoutDoubleCounting() {
        #expect(DemoPortfolioData.total(.all) == DemoPortfolioData.total(.personal) + DemoPortfolioData.total(.quant))
        for scope in PortfolioScope.allCases {
            let holdings = DemoPortfolioData.combined(scope)
            #expect(Set(holdings.map(\.symbol)).count == holdings.count)
            #expect(abs(holdings.reduce(0) { $0 + $1.value } + DemoPortfolioData.cash(scope) - DemoPortfolioData.total(scope)) < 0.001)
            #expect(abs(DesktopPortfolioMetrics.allocation(for: scope).reduce(0) { $0 + $1.value } - DemoPortfolioData.total(scope)) < 0.001)
            #expect(abs(DemoPortfolioData.total(scope) - DemoPortfolioData.principal(scope) - DemoPortfolioData.pnl(scope)) < 0.001)
        }
    }

    @Test func weightedCostPreservesSharedOwnership() throws {
        let nvda = try #require(DemoPortfolioData.combined(.all).first { $0.symbol == "NVDA" })
        #expect(nvda.quantity == 50)
        #expect(nvda.cost == 123)
        #expect(nvda.pnl == 850)
        #expect(nvda.value == 7000)
        #expect(DemoPortfolioData.lots(.personal).first { $0.symbol == "NVDA" }?.quantity == 20)
        #expect(DemoPortfolioData.lots(.quant).first { $0.symbol == "NVDA" }?.quantity == 30)
    }

    @Test func curveEndsAtAccountValueForEveryScope() throws {
        for scope in PortfolioScope.allCases {
            let points = DemoPortfolioData.points(scope)
            let last = try #require(points.last)
            #expect(abs(last.equity - DemoPortfolioData.total(scope)) < 0.001)
            #expect(points.allSatisfy { $0.drawdown >= 0 && $0.drawdown < 1 })
            for index in points.indices {
                let combined = DemoPortfolioData.points(.all)[index].equity
                let sum = DemoPortfolioData.points(.personal)[index].equity + DemoPortfolioData.points(.quant)[index].equity
                #expect(abs(combined - sum) < 0.001)
            }
        }
    }

    @Test func verticalMorphPreservesPointCorrespondence() {
        let start = [0.1, 0.8, 0.2, 0.4]
        let target = [0.7, 0.4, 0.9, 0.2]
        #expect(VerticalTrendMorph.values(from: start, to: target, progress: 0) == start)
        let final = VerticalTrendMorph.values(from: start, to: target, progress: 1)
        for index in start.indices { #expect(abs(final[index] - target[index]) < 0.000001) }
        let halfway = VerticalTrendMorph.values(from: start, to: target, progress: 0.5)
        for index in start.indices { #expect(abs(halfway[index] - (start[index] + target[index]) / 2) < 0.000001) }
        #expect(VerticalTrendMorph.resample([2, 10], count: 5) == [2, 4, 6, 8, 10])
        #expect(VerticalTrendMorph.resample([], count: 5).isEmpty)
    }

    @Test func amountAndReturnUseTheSamePrincipal() {
        for scope in PortfolioScope.allCases {
            let total = DemoPortfolioData.total(scope)
            let principal = DemoPortfolioData.principal(scope)
            #expect(PortfolioTrendMetric.amount.value(for: total, principal: principal) == total)
            #expect(abs(PortfolioTrendMetric.returnRate.value(for: total, principal: principal) - DemoPortfolioData.pnl(scope) / principal * 100) < 0.000001)
        }
        #expect(PortfolioTrendMetric.returnRate.value(for: 100, principal: 0).isFinite)
    }

    @Test func moomooPositionDecodingRetainsETFAndCost() throws {
        let json = #"{"code":"US.SPY","name":"S&P 500 ETF","qty":40,"cost_price":540,"market_val":23200,"pl_val":1600,"pl_ratio":7.4074,"realized_pl":0,"unrealized_pl":1600,"asset_class":"ETF"}"#
        let position = try JSONDecoder().decode(Position.self, from: Data(json.utf8))
        #expect(position.isEtf)
        #expect(position.currentPrice == 580)
        #expect(position.asPortfolioAsset.source == "moomoo")
        #expect(position.asPortfolioAsset.marketValue == 23200)
        let decodedAgain = try JSONDecoder().decode(Position.self, from: JSONEncoder().encode(position))
        #expect(decodedAgain.avgCost == position.avgCost)
        #expect(decodedAgain.isEtf)
    }

    @Test func previewCannotCreateBrokerRequestsOrCacheAccountData() {
        #expect(DemoPortfolioData.enabled)
        #expect(BackendConfig.url(path: "account") == nil)
        #expect(BackendConfig.url(path: "positions") == nil)
        #expect(DemoOfflineProtocol.canInit(with: URLRequest(url: URL(string: "https://example.com")!)))
        CacheManager.save(["value": 123], key: "test_demo_offline_cache")
        #expect(CacheManager.load([String: Int].self, key: "test_demo_offline_cache") == nil)
    }

    @Test func scopeChangesFilterOrdersNoticesAndAssetsTogether() {
        let demo = PortfolioDemo()
        demo.scope = .personal
        #expect(demo.notices.allSatisfy { $0.owner != .quant })
        #expect(demo.orders.count == 1)
        #expect(demo.orders.first?.displaySymbol == "AAPL")
        demo.scope = .quant
        #expect(demo.crypto.isEmpty)
        #expect(demo.orders.first?.displaySymbol == "NVDA")
        demo.acknowledged.insert("n1")
        #expect(demo.pendingCritical.isEmpty)
        #expect(demo.notices.contains { $0.id == "n1" })
    }

    @Test func intradayDemoUsesDistinctIndicesAndCoherentSummaries() throws {
        var prices: [Double] = []
        for symbol in ["IXIC", "SPX", "DJI"] {
            let model = IntradayPriceViewModel()
            model.loadDemo(symbol: symbol)
            let summary = try #require(model.summary)
            #expect(model.points.count == 48)
            #expect(model.points.last?.curPrice == summary.price)
            #expect(model.source == "demo")
            prices.append(try #require(summary.price))
        }
        #expect(Set(prices).count == 3)
    }
}
