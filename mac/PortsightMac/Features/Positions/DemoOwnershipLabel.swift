import SwiftUI
import Charts
import PortSightKit
struct DemoOwnershipLabel: View {
    @EnvironmentObject private var demo: PortfolioDemo
    let symbol: String
    /// The lots of this symbol in the current scope (Portfolio.lots: real IBKR lots once paired, built-in elsewhere).
    private var lots: [DemoHolding] { demo.lots(demo.scope).filter { $0.symbol == symbol } }
    var body: some View {
        HStack(spacing: 7) {
            ForEach(lots) { lot in
                Text(lot.owner.rawValue + " " + lot.quantity.formatted(.number.precision(.fractionLength(0...4))))
                    .font(.caption2).foregroundStyle(lot.owner == .quant ? .orange : .blue)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background((lot.owner == .quant ? Color.orange : .blue).opacity(0.08), in: Capsule())
            }
        }
    }
}
