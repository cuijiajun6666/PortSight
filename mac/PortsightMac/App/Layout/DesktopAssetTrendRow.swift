import SwiftUI
import PortSightKit

/// Give the summary its natural width and the chart every remaining point.
struct DesktopAssetTrendRow: Layout {
    var spacing: CGFloat = 24
    var minimumChartWidth: CGFloat = 180

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let summary = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: proposal.width ?? summary.width + spacing + 320,
                      height: proposal.height ?? max(summary.height, 180))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let idealWidth = subviews[0].sizeThatFits(.unspecified).width
        let summaryWidth = min(idealWidth, max(0, bounds.width - spacing - minimumChartWidth))
        let chartWidth = max(0, bounds.width - summaryWidth - spacing)
        subviews[0].place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: summaryWidth, height: bounds.height))
        subviews[1].place(at: CGPoint(x: bounds.minX + summaryWidth + spacing, y: bounds.minY),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: chartWidth, height: bounds.height))
    }
}
