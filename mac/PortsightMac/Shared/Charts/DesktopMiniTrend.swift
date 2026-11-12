import SwiftUI
import PortSightKit
struct DesktopMiniTrend: View {
    let symbol: String
    @StateObject private var model = IntradayPriceViewModel()
    /// Pairing redraws the curve: a symbol held for real then ends at IBKR's price (RelayNotices.usesRelay reads this).
    @ObservedObject private var server = ServerStore.shared
    var body: some View {
        IntradaySparklineChart(points: model.points, height: 30, maximumPointCount: 40, tintColor: DesktopTheme.blue.opacity(0.7))
            .task(id: "\(symbol)|\(RelayNotices.usesRelay)") { model.loadDemo(symbol: symbol) }
            .accessibilityHidden(true)
    }
}
