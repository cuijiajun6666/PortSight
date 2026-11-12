import SwiftUI
import Charts
import PortSightKit

struct DesktopMarketView: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @EnvironmentObject private var market: MarketStatusViewModel
    @State private var selected = "IXIC"
    @StateObject private var model = IntradayPriceViewModel()
    /// Pairing switches the holdings between the built-in ones and the mixed ones (real IBKR positions with built-in
    /// fillers); RelayNotices.usesRelay reads this.
    @ObservedObject private var server = ServerStore.shared
    private let indices = [("IXIC", "NASDAQ", "纳斯达克综合指数"), ("SPX", "S&P 500", "标普 500 指数"), ("DJI", "DOW JONES", "道琼斯工业指数")]
    var body: some View {
        DesktopPageScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 18) {
                    ForEach(indices, id: \.0) { index in
                        Button { selected = index.0 } label: {
                            DesktopIndexCard(symbol: index.0, title: index.1, subtitle: index.2, selected: selected == index.0)
                        }.buttonStyle(.plain)
                    }
                }
                DesktopCard {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            DesktopSectionTitle(title: indices.first { $0.0 == selected }?.1 ?? selected, subtitle: "美股分时走势 · 最近交易日")
                            Spacer()
                            // The US session from the New York clock (MarketStatusViewModel.applyClock).
                            DesktopPill(text: market.displayStatus, color: market.session == .regular ? DesktopTheme.green : .secondary)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text((model.summary?.price ?? 0).formatted(.number.precision(.fractionLength(2))))
                                .font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                            Text(String(format: "%+.2f (%+.2f%%)", model.summary?.change ?? 0, model.summary?.changePercent ?? 0))
                                .font(.system(size: 13)).foregroundStyle(DesktopTheme.green)
                        }
                        Chart(model.points) { point in
                            if let date = point.date {
                                AreaMark(x: .value("时间", date), yStart: .value("基线", floorPrice), yEnd: .value("价格", point.curPrice))
                                    .foregroundStyle(LinearGradient(colors: [DesktopTheme.blue.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom))
                                    .interpolationMethod(.catmullRom)
                                LineMark(x: .value("时间", date), y: .value("价格", point.curPrice))
                                    .foregroundStyle(DesktopTheme.blue).lineStyle(StrokeStyle(lineWidth: 2.2)).interpolationMethod(.catmullRom)
                            }
                        }
                        .chartYScale(domain: floorPrice...ceilingPrice)
                        .chartXAxis { AxisMarks(values: .stride(by: .hour)) { _ in AxisValueLabel(format: .dateTime.hour().minute()) } }
                        .chartYAxis { AxisMarks(position: .trailing) { _ in AxisGridLine(); AxisValueLabel() } }
                        .frame(height: 300)
                        HStack {
                            Text("市场走势 · 数据截至最近交易日").font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                            Text("USD").font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                    }
                }
                DesktopCard {
                    VStack(alignment: .leading, spacing: 22) {
                        DesktopSectionTitle(title: "持仓关注", subtitle: demo.scope.rawValue + "资产范围")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 225), spacing: 24)], spacing: 24) {
                            ForEach(demo.holdings) { holding in
                                HStack(spacing: 10) {
                                    DesktopSymbol(symbol: holding.symbol, crypto: SymbolLogoStore.isCrypto(holding.symbol, kind: holding.kind))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(holding.symbol).font(.system(size: 12, weight: .semibold))
                                        Text(DesktopTheme.money(holding.price)).font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    DesktopMiniTrend(symbol: holding.symbol).frame(width: 75)
                                }
                            }
                        }
                    }
                }
            }
        }.scrollIndicators(.hidden)
        .task(id: "\(selected)|\(RelayNotices.usesRelay)") { model.loadDemo(symbol: selected) }
    }
    private var floorPrice: Double { (model.points.map(\.curPrice).min() ?? 0) * 0.998 }
    private var ceilingPrice: Double { max((model.points.map(\.curPrice).max() ?? 1) * 1.002, floorPrice + 1) }
}

private struct DesktopIndexCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    let selected: Bool
    @StateObject private var model = IntradayPriceViewModel()
    @ObservedObject private var server = ServerStore.shared
    var body: some View {
        DesktopCard(padding: 22) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text(title).font(.system(size: 11, weight: .semibold)).tracking(1)
                    Spacer()
                    Circle().fill(selected ? DesktopTheme.blue : .clear).frame(width: 6, height: 6)
                }
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                Text((model.summary?.price ?? 0).formatted(.number.precision(.fractionLength(2))))
                    .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                HStack {
                    Text(String(format: "%+.2f%%", model.summary?.changePercent ?? 0)).font(.system(size: 11, weight: .medium)).foregroundStyle(DesktopTheme.green)
                    Spacer()
                    IntradaySparklineChart(points: model.points, height: 36, tintColor: DesktopTheme.blue).frame(width: 90)
                }
            }
        }.overlay { DesktopTheme.surfaceShape.strokeBorder(selected ? DesktopTheme.blue.opacity(0.5) : .clear, lineWidth: 1) }
            .task(id: RelayNotices.usesRelay) { model.loadDemo(symbol: symbol) }
    }
}
