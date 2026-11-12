import SwiftUI
import PortSightKit

/// Allocation and account totals share the asset card, without nested card surfaces.
struct DesktopAllocationSummary: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @State private var viewportWidth: CGFloat = 0
    var openPositions: () -> Void
    var openAsset: (PortfolioAsset) -> Void

    var body: some View {
        ScrollView(.horizontal) {
        HStack(alignment: .top, spacing: 12) {
            DesktopAllocationContent(items: DesktopPortfolioMetrics.allocation(for: demo.scope),
                                     scope: demo.scope, total: demo.total, cash: demo.cash,
                                     compact: true, horizontal: true, openPositions: openPositions)
                .frame(minWidth: 260, maxWidth: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 20) {
                accountAmount(scope: .personal, title: "个人投资", icon: "person")
                accountAmount(scope: .quant, title: "量化投资", icon: "cpu")
            }
            .fixedSize(horizontal: true, vertical: false)
            Divider()
            VStack(alignment: .leading, spacing: 20) {
                amount(title: "可用现金", value: demo.cash,
                       detail: "占总资产 " + DesktopTheme.share(demo.cash, of: demo.total))
                amount(title: "持仓市值", value: demo.total - demo.cash,
                       detail: "\(demo.holdings.count) 项资产")
            }
            .fixedSize(horizontal: true, vertical: false)
            Divider()
            compactHoldings
                .frame(width: 228)
        }
        .frame(minWidth: viewportWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        }
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            viewportWidth = width
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var compactHoldings: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("主要持仓").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("查看全部持仓", systemImage: "arrow.up.right", action: openPositions)
                    .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
                    .controlSize(.mini).foregroundStyle(.primary)
            }
            ForEach(Array(demo.holdings.prefix(5))) { holding in
                Button { openAsset(holding.asset) } label: {
                    HStack(spacing: 6) {
                        DesktopSymbol(symbol: holding.symbol, crypto: SymbolLogoStore.isCrypto(holding.symbol, kind: holding.kind), size: 22)
                        Text(holding.symbol).fontWeight(.medium)
                        Spacer(minLength: 4)
                        Text(DesktopTheme.money(holding.value, decimals: 0)).monospacedDigit()
                        Text(DesktopTheme.share(holding.value, of: demo.total, digits: 0))
                            .foregroundStyle(.secondary).monospacedDigit()
                            .frame(width: 38, alignment: .trailing)
                    }
                    .font(.system(size: 15)).lineLimit(1)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(holding.name + " · 占总资产比例")
            }
        }
    }

    private func accountAmount(scope: PortfolioScope, title: String, icon: String) -> some View {
        Button { withAnimation(.smooth) { demo.scope = scope } } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon).font(.system(size: 12)).foregroundStyle(.secondary)
                // 个人: the IBKR account once paired; 量化: built in (Portfolio).
                Text(DesktopTheme.money(demo.total(scope)))
                    .font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(DesktopTheme.percent(demo.pnl(scope), of: demo.principal(scope)))
                    .font(.system(size: 11)).foregroundStyle(DesktopTheme.pnlColor(demo.pnl(scope)))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("查看" + title)
    }

    private func amount(title: String, value: Double, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(DesktopTheme.money(value))
                .font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
