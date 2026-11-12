import SwiftUI
import PortSightKit

/// Shared allocation content, usable inside the asset card without another surface.
struct DesktopAllocationContent: View {
    let items: [AllocationItem]
    let scope: PortfolioScope
    let total: Double
    let cash: Double
    var compact = false
    var horizontal = false
    var openPositions: () -> Void

    var body: some View {
        Group {
            if horizontal {
                horizontalContent
            } else {
                verticalContent
            }
        }
        .accessibilityIdentifier("allocation_content")
    }

    private var horizontalContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                DesktopSectionTitle(title: "资产配置")
                Spacer()
                investedRatio
                positionsButton
            }
            HStack(spacing: compact ? 12 : 24) {
                AllocationDonutChart(items: items, animationKey: scope.rawValue,
                                     verticalLayout: true, diameter: 132, showsLegend: false)
                    .fixedSize()
                allocationLegend(expanded: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: 132)
            }
        }
    }

    private var verticalContent: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            DesktopSectionTitle(title: "资产配置")
            Spacer(minLength: 0)
            AllocationDonutChart(items: items, animationKey: scope.rawValue,
                                 verticalLayout: true, diameter: 132, showsLegend: false)
                .fixedSize()
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            if compact {
                legend
                HStack {
                    investedRatio
                    Spacer(minLength: 8)
                    positionsButton
                }
            } else {
                HStack(spacing: 12) {
                    legend
                    Divider().frame(height: 64)
                    investedRatio
                    positionsButton
                }
            }
        }
    }

    private var legend: some View {
        allocationLegend(expanded: false)
    }

    private func allocationLegend(expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: expanded ? 4 : 7) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 6) {
                    Circle().fill(color(for: index, name: item.name)).frame(width: 6, height: 6)
                    Text(item.name == "Cash" ? "现金" : item.name)
                    Spacer(minLength: 4)
                    Text(DesktopTheme.money(item.value, decimals: 0))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.system(size: 14))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var investedRatio: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("投资比例").font(.system(size: 10)).foregroundStyle(.secondary)
            Text(total > 0 ? (total - cash) / total : 0,
                 format: .percent.precision(.fractionLength(1)))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private var positionsButton: some View {
        Button(action: openPositions) {
            Label("查看全部持仓", systemImage: "arrow.up.right")
                .foregroundStyle(.primary)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help("查看全部持仓")
        .accessibilityIdentifier("allocation_positions")
    }
}
