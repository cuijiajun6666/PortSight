import Foundation
// These totals use the same lots and weighted-cost model as iOS.
// Cash appears once; shared symbols are combined before rendering.
public enum DesktopPortfolioMetrics {
    public static func allocation(for scope: PortfolioScope) -> [AllocationItem] {
        let grouped = Dictionary(grouping: Portfolio.combined(scope), by: \.kind)
        var items = grouped.map { AllocationItem(name: $0.key, value: $0.value.reduce(0) { $0 + $1.value }) }
        let cash = Portfolio.cash(scope)
        if !Portfolio.isLive || cash != 0 { items.append(AllocationItem(name: "Cash", value: cash)) }
        return items.sorted { $0.value > $1.value }
    }
    public static func maxDrawdown(for scope: PortfolioScope) -> Double {
        // Once live there is no value history yet (Portfolio.points is empty): 0, and the pages say 尚未接入.
        Portfolio.points(scope).map(\.drawdown).max() ?? 0
    }
}

