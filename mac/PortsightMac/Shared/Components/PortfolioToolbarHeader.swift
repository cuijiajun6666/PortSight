//
//  PortfolioToolbarHeader.swift
//  PortSight
//
//  Created by Chris Cui on 28/4/2026.
//
import SwiftUI
import SwiftData
import PortSightKit

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
    var metric: PortfolioTrendMetric = .amount
    
    var body: some View {
        
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                if metric == .amount {
                    AssetText(value: selectedAssetValue ?? vm.totalAsset)
                } else {
                    let value = metric.value(for: selectedAssetValue ?? vm.totalAsset, principal: vm.principalTotal)
                    Text(vm.principalTotal > 0 ? String(format: "%+.2f%%", value) : "—")
                        .font(.largeTitle.bold())
                        .contentTransition(.numericText())
                        .animation(.easeInOut, value: value)
                }
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
    func body(content: Content) -> some View { content.toolbar { DemoToolbar() } }
}

struct DemoAssetHeader: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @EnvironmentObject private var market: MarketStatusViewModel
    @ObservedObject var vm: AssetViewModel
    let selectedAssetValue: Double?
    @Binding var metric: PortfolioTrendMetric
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                HStack(spacing: 14) {
                    ForEach(PortfolioTrendMetric.allCases) { option in
                        Button {
                            metric = option
                        } label: {
                            Text(option.rawValue)
                                .font(.caption.weight(metric == option ? .semibold : .regular))
                                .foregroundStyle(metric == option ? .primary : .secondary)
                                .scaleEffect(metric == option ? 1.12 : 1)
                                .animation(.spring(response: 0.32, dampingFraction: 0.65), value: metric)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(metric == option ? "已选择" : "")
                        .accessibilityHint("同时更新顶部数字和走势图")
                    }
                }
                Spacer()
            }
            PortfolioToolbarHeader(vm: vm, selectedAssetValue: selectedAssetValue, metric: metric)
            HStack(spacing: 3) {
                // Once paired the IBKR P&L can be a loss: signed and coloured by its sign.
                if demo.isLive {
                    Text(DesktopTheme.signedMoney(demo.pnl))
                    Text("(" + (demo.principal != 0 ? demoPercent(demo.pnl / demo.principal) : "—") + ")")
                } else {
                    Text("+" + demoMoney(demo.pnl))
                    Text("(" + demoPercent(demo.pnl / demo.principal) + ")")
                }
                Text("Total").foregroundStyle(.secondary).padding(.leading, 2)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(demo.isLive ? DesktopTheme.pnlColor(demo.pnl) : .green)
            .contentTransition(.numericText())
            // 「非实时 · 截至 …」 while the IBKR figures are real but not live.
            if let note = demo.liveNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                // The US session from the New York clock (MarketStatusViewModel.applyClock).
                HStack(spacing: 4) {
                    MarketSessionIndicator(session: market.session)
                    Text(market.displayStatus).foregroundStyle(.secondary).font(.caption)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassEffect(.regular.interactive())
                HStack(spacing: 6) {
                    Circle().fill(.blue).frame(width: 7, height: 7)
                    Text("已连接").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .glassEffect(.regular.interactive())
                Spacer()
            }.padding(.top, 5)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.25), value: demo.scope)
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

