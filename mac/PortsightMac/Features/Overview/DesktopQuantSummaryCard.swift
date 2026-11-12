import SwiftUI
import PortSightKit

struct DesktopQuantSummaryCard: View {
    @EnvironmentObject private var demo: PortfolioDemo
    var openStrategies: () -> Void

    // Match the two holding groups shown on the strategy page. These are
    // position returns, not time-weighted strategy returns or live statuses.
    private var strategies: [StrategySummary] {
        [("核心 ETF 趋势", "ETF"), ("量化选股", "股票")].compactMap { name, kind in
            let holdings = demo.lots(.quant).filter { $0.kind == kind }
            guard !holdings.isEmpty else { return nil }
            let cost = holdings.reduce(0) { $0 + $1.quantity * $1.cost }
            let pnl = holdings.reduce(0) { $0 + $1.pnl }
            return StrategySummary(name: name, pnl: pnl, returnRate: cost > 0 ? pnl / cost : 0)
        }.sorted { $0.returnRate > $1.returnRate }
    }

    var body: some View {
        DesktopCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    DesktopSectionTitle(title: demo.scope == .quant ? "策略表现对比" : "量化表现")
                    Spacer()
                    Button("查看策略", systemImage: "arrow.up.right", action: openStrategies)
                        .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
                        .foregroundStyle(.primary)
                }
                // The quant account is built in, paired or not (Portfolio).
                figures
            }
            .frame(minHeight: 240, alignment: .topLeading)
        }
        .accessibilityIdentifier("dashboard_quant_summary")
    }

    @ViewBuilder private var figures: some View {
        if demo.scope == .all {
            VStack(alignment: .leading, spacing: 3) {
                Text(DesktopTheme.signedMoney(demo.pnl(.quant)))
                    .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(DesktopTheme.pnlColor(demo.pnl(.quant)))
                Text("量化累计收益 · " + DesktopTheme.percent(demo.pnl(.quant), of: demo.principal(.quant)))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        HStack {
            Text("监控策略")
            Spacer()
            Text("\(strategies.count) 个").fontWeight(.semibold)
        }.font(.system(size: 12))
        Divider()
        ForEach(strategies) { strategy in
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(strategy.name).font(.system(size: 12, weight: .medium))
                    Text(DesktopTheme.signedMoney(strategy.pnl))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(DesktopTheme.percent(strategy.returnRate))
                    .font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(DesktopTheme.pnlColor(strategy.returnRate))
            }
        }
        Spacer(minLength: 0)
        Text("按持仓成本收益率排序 · 不含策略现金")
            .font(.system(size: 10)).foregroundStyle(.secondary)
    }
}

private struct StrategySummary: Identifiable {
    let name: String
    let pnl: Double
    let returnRate: Double
    var id: String { name }
}
