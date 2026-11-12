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
            .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
            .contentTransition(.numericText())
            .animation(.easeInOut, value: value)
    }
}

struct PortfolioToolbarHeader: View {
    @ObservedObject var vm: AssetViewModel
    let selectedAssetValue: Double?
    var metric: PortfolioTrendMetric = .amount
    /// 收益率 of the chart's own return curve (the range's time-weighted return, percentage points) when it has one;
    /// the selected value is then a return too. nil: worked out from the principal as before.
    var rangeReturn: Double? = nil

    var body: some View {

        HStack {
            VStack(alignment: .leading, spacing: 0) {
                if metric == .amount {
                    AssetText(value: selectedAssetValue ?? vm.totalAsset)
                } else if let rangeReturn {
                    let value = selectedAssetValue ?? rangeReturn
                    Text(String(format: "%+.2f%%", value))
                        .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeInOut, value: value)
                } else {
                    let value = metric.value(for: selectedAssetValue ?? vm.totalAsset, principal: vm.principalTotal)
                    Text(vm.principalTotal > 0 ? String(format: "%+.2f%%", value) : "—")
                        .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
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
    @ObservedObject var vm: AssetViewModel
    let selectedAssetValue: Double?
    @Binding var metric: PortfolioTrendMetric
    /// The value chart's range (the picker under it).
    var range: IBKREquityRange = .standard
    /// The range's real history while it is on the chart (else the built-in curve is).
    var equity: IBKREquity? = nil
    /// 收益率 of the chart's own return curve (percentage points), when it has one.
    var rangeReturn: Double? = nil

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
                .sensoryFeedback(.selection, trigger: metric)
                Spacer()
            }
            PortfolioToolbarHeader(vm: vm, selectedAssetValue: selectedAssetValue, metric: metric,
                                   rangeReturn: rangeReturn)
            if let equity, let pnl = equity.pnl {
                RangePnLSummary(range: range, pnl: pnl, twr: equity.twr).padding(.top, 2)
            } else {
                PnLSummary().padding(.top, 2)
            }
            // Once paired, while the IBKR figures are real but not live: 「非实时 · 截至 …」.
            if let note = demo.liveNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.25), value: demo.scope)
    }
}

/// 累计 replaced by the chart range's cumulative P&L and time-weighted return (「1月 +$450.00 · +4.50%」) while the
/// range's real history is on the chart, then 今日 as in PnLSummary.
struct RangePnLSummary: View {
    @EnvironmentObject private var demo: PortfolioDemo
    let range: IBKREquityRange
    let pnl: Double
    let twr: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            line(range.title, terminalSignedMoney(pnl) + (twr.map { " · " + TerminalFormat.percent($0) } ?? ""),
                 value: pnl)
            // Today's move against yesterday's close (no percentage without one).
            let previous = demo.total - demo.dayPnL
            line("今日", terminalSignedMoney(demo.dayPnL)
                 + (previous > 0 ? " · " + TerminalFormat.percent(demo.dayPnL / previous) : ""), value: demo.dayPnL)
        }
        .font(.subheadline)
        .animation(.smooth, value: demo.scope)
        .animation(.smooth, value: range)
    }

    private func line(_ label: String, _ text: String, value: Double) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(.secondary)
                .contentTransition(.interpolate)
            Text(text).fontWeight(.semibold).foregroundStyle(TerminalStyle.pnl(value)).monospacedDigit()
                .contentTransition(.numericText(value: value))
        }
    }
}

struct MarketSessionIndicator: View {
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
    DashboardView(selectedTab: .constant(0)).environmentObject(PortfolioDemo())
        .modelContainer(for: [Item.self, AssetSnapshotRecord.self, StockLogoRecord.self], inMemory: true)
}
