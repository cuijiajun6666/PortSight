import Testing
@testable import PortSight
import PortSightKit

struct PortfolioDemoTests {
    @Test func scopesReconcileWithoutDoubleCountingCash() {
        #expect(DemoPortfolioData.total(.all) == DemoPortfolioData.total(.personal) + DemoPortfolioData.total(.quant))
        for scope in PortfolioScope.allCases {
            let holdings = DemoPortfolioData.combined(scope)
            #expect(abs(holdings.reduce(0) { $0 + $1.value } + DemoPortfolioData.cash(scope) - DemoPortfolioData.total(scope)) < 0.001)
            #expect(Set(holdings.map(\.symbol)).count == holdings.count)
        }
    }
    @Test func sharedSymbolKeepsOwnershipAndWeightedCost() {
        let combined = DemoPortfolioData.combined(.all).first { $0.symbol == "NVDA" }!
        #expect(combined.quantity == 50)
        #expect(abs(combined.pnl - 850) < 0.001)
        #expect(DemoPortfolioData.lots(.personal).first { $0.symbol == "NVDA" }?.quantity == 20)
        #expect(DemoPortfolioData.lots(.quant).first { $0.symbol == "NVDA" }?.quantity == 30)
    }
    @Test func chartsEndAtDisplayedBalancesAndAddAcrossScopes() {
        for scope in PortfolioScope.allCases {
            #expect(abs(DemoPortfolioData.points(scope).last!.equity - DemoPortfolioData.total(scope)) < 0.001)
        }
        for i in 0..<30 {
            #expect(abs(DemoPortfolioData.points(.all)[i].equity - DemoPortfolioData.points(.personal)[i].equity - DemoPortfolioData.points(.quant)[i].equity) < 0.001)
        }
    }
    @MainActor @Test func acknowledgingCriticalRemovesBannerWithoutDeletingNotice() {
        let demo = PortfolioDemo()
        #expect(demo.pendingCritical.count == 1)
        demo.acknowledged.insert("n1")
        #expect(demo.pendingCritical.isEmpty)
        #expect(demo.notices.contains { $0.id == "n1" })
        demo.scope = .personal
        #expect(demo.notices.allSatisfy { $0.owner != .quant })
        demo.scope = .quant
        #expect(demo.holdings.allSatisfy { $0.kind != "加密货币" })
    }
}
