import SwiftUI
import PortSightKit
struct CryptoHoldingRow: View {
    let holding: MockCryptoHolding
    let price: Double?

    private var currentPrice: Double {
        price ?? 0
    }

    private var marketValue: Double {
        holding.quantity * currentPrice
    }

    private var pnl: Double {
        (currentPrice - holding.avgCost) * holding.quantity
    }

    private var pnlRatio: Double {
        holding.avgCost > 0 ? (currentPrice - holding.avgCost) / holding.avgCost * 100 : 0
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    // The coin's real icon (SymbolLogoStore), like a stock row's.
                    DesktopSymbolLogo(symbol: holding.symbol, crypto: true, size: 20)

                    Text(holding.symbol)
                        .font(.headline)
                }

                Text("\(holding.quantity, specifier: "%.4f") 枚")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("市值: $\(marketValue, specifier: "%.2f")")
                    .font(.caption)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: marketValue)
            }

            Spacer()
            
            Text("图表")
            
            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(pnl >= 0 ? "+" : "-")$\(abs(pnl), specifier: "%.2f")")
                    .font(.headline)
                    .foregroundStyle(pnl >= 0 ? .green : .red)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: pnl)

                Text("\(pnlRatio >= 0 ? "+" : "-")\(abs(pnlRatio), specifier: "%.2f")%")
                    .font(.caption)
                    .foregroundStyle(pnl >= 0 ? .green : .red)

                Text("现价: $\(currentPrice, specifier: "%.2f")")
                    .font(.caption)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: currentPrice)
            }
        }
    }
}



