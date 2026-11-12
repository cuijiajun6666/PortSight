import SwiftUI
import Charts
import PortSightKit

struct DesktopAnalysisView: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @State private var period = "1M"
    /// Pairing switches the figures between the built-in portfolio and live (RelayNotices.usesRelay reads this).
    @ObservedObject private var server = ServerStore.shared
    /// The value curve is read from the relay only while the window is in front.
    @Environment(\.desktopAppActive) private var appActive
    let openSheet: (DesktopSheet) -> Void
    private func shown(_ all: [PortfolioCurvePoint]) -> [PortfolioCurvePoint] {
        period == "1W" ? Array(all.suffix(7)) : all
    }
    /// Return over the picked period, deposits and withdrawals left out.
    private func intervalReturn(_ points: [PortfolioCurvePoint]) -> Double {
        guard let first = points.first, let last = points.last, first.growth != 0 else { return 0 }
        return last.growth / first.growth - 1
    }
    /// The largest holding's share of the total (never a division by zero).
    private var largestShare: String {
        guard let largest = demo.holdings.first else { return "—" }
        return DesktopTheme.share(largest.value, of: demo.total)
    }
    var body: some View {
        // The value curve over the standard range (1月): the real IBKR curve once it has been read, else the built-in
        // one; the benchmark is built in either way (the relay has none).
        let curve = PortfolioCurve(scope: demo.scope)
        let points = shown(curve.points)
        DesktopPageScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 16) {
                    DesktopMetricCard(title: "累计收益率", value: DesktopTheme.percent(demo.pnl, of: demo.principal), detail: "按固定本金计算", icon: "arrow.up.right", tint: DesktopTheme.green)
                    DesktopMetricCard(title: "区间最大回撤", value: String(format: "%.2f%%", curve.maxDrawdown * 100), detail: "从历史峰值到低点", icon: "chart.line.downtrend.xyaxis", tint: DesktopTheme.orange)
                    DesktopMetricCard(title: "最大单一持仓", value: largestShare, detail: demo.holdings.first?.name ?? "—", icon: "circle.lefthalf.filled", tint: .purple)
                }
                // 「非实时 · 截至 …」 while the IBKR figures are not live.
                if let note = demo.liveNote {
                    Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("analysis_live_note")
                }
                DesktopCard {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack {
                            DesktopSectionTitle(title: "组合与基准",
                                                subtitle: curve.isReal ? "区间起点归零 · 出入金不计入收益" : "区间起点归零 · 期间无外部现金流")
                            Spacer()
                            DesktopCapsulePicker(title: "区间", options: ["1W", "1M"], selection: $period) { $0 }.labelsHidden()
                            Button("收益复盘 ↗") { openSheet(.report) }.buttonStyle(.glass).foregroundStyle(.primary).padding(.leading, 15)
                        }
                        let change = intervalReturn(points)
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(DesktopTheme.percent(change)).font(.system(size: 40, weight: .semibold, design: .rounded)).foregroundStyle(DesktopTheme.pnlColor(change))
                            Text("区间收益").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Chart {
                            ForEach(points) { point in
                                if let first = points.first, first.growth != 0, first.benchmark != 0 {
                                    LineMark(x: .value("日期", point.date), y: .value("收益率", (point.growth / first.growth - 1) * 100))
                                        .foregroundStyle(by: .value("组合", "我的组合")).interpolationMethod(.catmullRom)
                                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                                    LineMark(x: .value("日期", point.date), y: .value("收益率", (point.benchmark / first.benchmark - 1) * 100))
                                        .foregroundStyle(by: .value("组合", "基准")).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                }
                            }
                        }.chartForegroundStyleScale(["我的组合": DesktopTheme.blue, "基准": Color.gray.opacity(0.55)])
                            .chartYAxis { AxisMarks { value in AxisGridLine(); AxisValueLabel { if let n = value.as(Double.self) { Text(String(format: "%.1f%%", n)) } } } }
                            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
                            .frame(height: 270)
                    }
                }
                HStack(alignment: .top, spacing: 20) {
                    DesktopCard {
                        VStack(alignment: .leading, spacing: 22) {
                            DesktopSectionTitle(title: "收益贡献", subtitle: "各项持仓的未实现盈亏")
                            if demo.holdings.isEmpty {
                                // Nothing held: one line, never an empty chart.
                                DesktopMissingNote("暂无持仓", height: 240)
                            } else {
                                Chart(demo.holdings.sorted { $0.pnl > $1.pnl }) { holding in
                                    BarMark(x: .value("盈亏", holding.pnl), y: .value("资产", holding.symbol), height: .ratio(0.55))
                                        .foregroundStyle(DesktopTheme.pnlColor(holding.pnl).opacity(0.8)).cornerRadius(4)
                                }.chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }.frame(height: 240)
                            }
                        }
                    }
                    DesktopCard {
                        VStack(alignment: .leading, spacing: 22) {
                            HStack {
                                DesktopSectionTitle(title: "回撤观察", subtitle: "相对历史高点的回落幅度")
                                Spacer()
                                Image(systemName: "shield.lefthalf.filled").foregroundStyle(DesktopTheme.orange)
                            }
                            Chart(curve.points) { point in
                                AreaMark(x: .value("日期", point.date), y: .value("回撤", -point.drawdown * 100))
                                    .foregroundStyle(DesktopTheme.orange.opacity(0.16))
                                LineMark(x: .value("日期", point.date), y: .value("回撤", -point.drawdown * 100))
                                    .foregroundStyle(DesktopTheme.orange).lineStyle(StrokeStyle(lineWidth: 1.5))
                            }.chartXAxis(.hidden).frame(height: 147)
                            Divider().opacity(0.5)
                            Button { openSheet(.fullAnalysis) } label: {
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text("查看模型评分与完整分析")
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }.font(.system(size: 12)).foregroundStyle(.primary)
                            }.buttonStyle(.glass)
                        }
                    }
                }
                NavigationStack { DemoInsightsAdditions().padding(.top, 16) }
                    .frame(height: 430).background(DesktopTheme.card, in: DesktopTheme.surfaceShape)
                    .clipShape(DesktopTheme.surfaceShape)
                    .modifier(DesktopCardShadow())
            }
        }.scrollIndicators(.hidden)
        // Once paired: the value curve (1月) every 10 s while the page is on screen and the app in front.
        .pollsIBKREquity(.standard, active: appActive)
    }
}
