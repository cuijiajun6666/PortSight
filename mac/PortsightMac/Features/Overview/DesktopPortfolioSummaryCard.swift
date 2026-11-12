import SwiftUI
import PortSightKit

/// Uses the same scope, history and benchmark as the analysis page.
struct DesktopPortfolioSummaryCard: View {
    @EnvironmentObject private var demo: PortfolioDemo
    var openAnalysis: () -> Void

    var body: some View {
        // The value curve over the standard range (1月): the real IBKR curve once it has been read, else the built-in
        // one; the benchmark is built in either way (the relay has none).
        let curve = PortfolioCurve(scope: demo.scope)
        DesktopCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    DesktopSectionTitle(title: "投资组合分析",
                                        subtitle: demo.scope.rawValue + (curve.isReal ? " · 近 1 月" : " · 近 30 个交易日"))
                    Spacer()
                    Button("查看分析", systemImage: "arrow.up.right", action: openAnalysis)
                        .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
                        .foregroundStyle(.primary)
                }
                metric("最大单一持仓", value: largestShare,
                       detail: (demo.holdings.first?.symbol ?? "—") + " · 占总资产", color: .primary)
                Divider()
                metric("区间最大回撤", value: String(format: "%.2f%%", curve.maxDrawdown * 100),
                       detail: "从历史峰值到低点", color: .primary)
                Divider()
                metric("相对基准", value: String(format: "%+.2f 个百分点", curve.excessReturn * 100),
                       detail: "组合收益率 − 基准收益率", color: DesktopTheme.pnlColor(curve.excessReturn))
            }
            .frame(minHeight: 240, alignment: .topLeading)
        }
        .accessibilityIdentifier("dashboard_analysis_summary")
    }

    /// The largest holding's share of the total (never a division by zero).
    private var largestShare: String {
        guard let largest = demo.holdings.first else { return "—" }
        return DesktopTheme.share(largest.value, of: demo.total)
    }

    private func metric(_ title: String, value: String, detail: String, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(value).font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}
