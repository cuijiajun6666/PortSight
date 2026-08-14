//
//  PortfolioToolbarHeader.swift
//  PortSight
//
//  Created by Chris Cui on 28/4/2026.
//
import SwiftUI
import SwiftData

struct AssetText: View {
    let value: Double
    
    var body: some View {
        Text("$\(value, specifier: "%.2f")")
            .font(.largeTitle.bold())
            .contentTransition(.numericText())
            .animation(.easeInOut, value: value)
    }
}

struct PortfolioToolbarHeader: View {
    @ObservedObject var vm: AssetViewModel
    let selectedAssetValue: Double?
    
    var body: some View {
        
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                AssetText(value: selectedAssetValue ?? vm.totalAsset)
            }
            
            Spacer()
        }
    }
}

struct PortfolioToolbarModifier: ViewModifier {
    @ObservedObject var vm: AssetViewModel
    @ObservedObject var positionsVM: PositionsViewModel
    @ObservedObject var quoteVM: QuoteViewModel
    @ObservedObject var marketVM: MarketStatusViewModel
    
    let selectedAssetValue: Double?
    
    private var totalPnL: Double {
        vm.totalAsset - vm.principalTotal
    }

    private var totalRatio: Double {
        vm.principalTotal > 0 ? totalPnL / vm.principalTotal * 100 : 0
    }

    private var totalCost: Double {
        positionsVM.positions.reduce(0) {
            $0 + ($1.quantity * $1.avgCost)
        }
    }

    private var dayPnL: Double {
        positionsVM.positions.reduce(0) { sum, position in
            guard let quote = quoteVM.quote(for: position.symbol),
                  let price = quote.price,
                  let prev = quote.prev_close_price else {
                return sum
            }
            return sum + (price - prev) * position.quantity
        }
    }
    private var dayRatio: Double {
        totalCost > 0 ? dayPnL / totalCost * 100 : 0
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                //连接状态
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        
                    } label: {
                        Image(systemName: "apple.intelligence")
                            .symbolRenderingMode(.multicolor)
                    }
                }



                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                }

                
                ToolbarItem(placement: .principal) {
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                HStack(spacing: 2) {
                                    MarketSessionIndicator(session: marketVM.session)

                                    Text(marketVM.displayStatus)
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                        .contentTransition(.numericText())
                                }
                                .contentTransition(.numericText())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4.5)
                                .padding(.leading, -5)
                                .glassEffect(.regular.interactive())
                                .offset(y: -15)
                                .animation(.easeInOut(duration: 0.22), value: marketVM.displayStatus)
                                
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(vm.isConnected ? .green : .red)
                                        .frame(width: 8, height: 8)
                                    
                                    Text(vm.connectionStatus)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .onTapGesture {
                                    Task {
                                        await vm.fetchAccount()
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .glassEffect(.regular.interactive())
                                .offset(y: -15)
                            }
                            .offset(y: -10)
                            HStack {
                                Text("Total Assets")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            PortfolioToolbarHeader(
                                vm: vm,
                                selectedAssetValue: selectedAssetValue
                            )
                            .task {
                                vm.startAutoRefresh()
                            }
                            
                            HStack(spacing: 1) {
                                Text("\(totalPnL >= 0 ? "+" : "-")$\(abs(totalPnL), specifier: "%.2f")")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(totalPnL >= 0 ? .green : .red)
                                    .contentTransition(.numericText())
                                    .animation(.easeInOut, value: totalPnL)
                                
                                Text("(\(totalRatio >= 0 ? "+" : "-")\(abs(totalRatio), specifier: "%.2f")%)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(totalPnL >= 0 ? .green : .red)
                                    .contentTransition(.numericText())
                                    .animation(.easeInOut, value: totalRatio)
                                
                                Text("Total")
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 2)
                            }
                            
//                            HStack(spacing: 1) {
//                                Text("\(dayPnL >= 0 ? "+" : "")$\(dayPnL, specifier: "%.2f")")
//                                    .font(.subheadline.weight(.semibold))
//                                    .foregroundStyle(dayPnL >= 0 ? .green : .red)
//                                    .contentTransition(.numericText())
//                                    .animation(.easeInOut, value: dayPnL)
//                                Text("(\(dayRatio >= 0 ? "+" : "")\(dayRatio, specifier: "%.2f")%)")
//                                    .font(.subheadline.weight(.semibold))
//                                    .foregroundStyle(dayPnL >= 0 ? .green : .red)
//                                    .contentTransition(.numericText())
//                                    .animation(.easeInOut, value: dayRatio)
//                                Text("Day")
//                                    .foregroundStyle(.secondary)
//                                    .padding(.leading, 2)
//                            }
                            //占位符
                            HStack(spacing: 1) {
                                Text("+$647.7")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.clear)
                                Text("+(1.26%)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.clear)
                                Text("Day")
                                    .foregroundStyle(.clear)
                                    .padding(.leading, 2)
                            }
                            HStack(spacing: 1) {
                                Text("+$647.7")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.clear)
                                Text("+(1.26%)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.clear)
                                Text("Day")
                                    .foregroundStyle(.clear)
                                    .padding(.leading, 2)
                            }
                            HStack(spacing: 1) {
                                Text("+$647.7")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.clear)
                                Text("+(1.26%)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.clear)
                                Text("Day")
                                    .foregroundStyle(.clear)
                                    .padding(.leading, 2)
                            }
                            HStack(spacing: 1) {
                                Text("+$647.7")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.clear)
                                Text("+(1.26%)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.clear)
                                Text("Day")
                                    .foregroundStyle(.clear)
                                    .padding(.leading, 2)
                            }
                            
                        }
                        
                        Spacer()
                    }
                    .offset(y: 95)
                }
            }
    }

}

private struct MarketSessionIndicator: View {
    @State private var radiates = false

    let session: MarketSession

    var body: some View {
        Group {
            switch session {
            case .unknown:
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 18, height: 18)

            case .regular, .pre, .after:
                ZStack {
                    Circle()
                        .stroke(Color.green.opacity(0.5), lineWidth: 1.2)
                        .frame(width: 9, height: 9)
                        .scaleEffect(radiates ? 2.25 : 1)
                        .opacity(radiates ? 0 : 0.85)

                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                }
                .frame(width: 18, height: 18)
                .onAppear {
                    radiates = true
                }
                .animation(
                    .easeOut(duration: 1.45).repeatForever(autoreverses: false),
                    value: radiates
                )

            case .overnight:
                Image(systemName: "moon.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 18, height: 18)

            case .closed:
                Circle()
                    .fill(.gray)
                    .frame(width: 8, height: 8)
                    .frame(width: 18, height: 18)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: session)
        .accessibilityHidden(true)
    }
}

extension View {
    func portfolioToolbar(
        vm: AssetViewModel,
        positionsVM: PositionsViewModel,
        quoteVM: QuoteViewModel,
        marketVM: MarketStatusViewModel,
        selectedAssetValue: Double?
    ) -> some View {
        self.modifier(
            PortfolioToolbarModifier(
                vm: vm,
                positionsVM: positionsVM,
                quoteVM: quoteVM,
                marketVM: marketVM,
                selectedAssetValue: selectedAssetValue
            )
        )
    }
}

#Preview {
    PortfolioToolbarHeader(
        vm: AssetViewModel(),
        selectedAssetValue: nil
    )
    .padding()
}

#Preview {
    DashboardView(selectedTab: .constant(0))
        .modelContainer(for: [Item.self, AssetSnapshotRecord.self, StockLogoRecord.self], inMemory: true)
}
