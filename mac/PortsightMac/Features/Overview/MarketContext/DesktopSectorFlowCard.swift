import SwiftUI
import PortSightKit

/// 概览's market card. It used to list 板块资金流向; it now shows the US-stock heatmap, whose tiles carry
/// both the day change and the net money flow.
struct DesktopSectorFlowCard: View {
    var body: some View {
        DesktopMarketHeatmapCard()
    }
}
