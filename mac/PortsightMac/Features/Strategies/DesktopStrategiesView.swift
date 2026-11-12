import SwiftUI
import Charts
import PortSightKit

struct DesktopStrategiesView: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @State private var showDetails = false
    /// The built-in quant portfolio, paired or not: the relay has no source for the quant account yet, so the page
    /// looks the same before and after pairing.
    private var quant: [DemoHolding] { DemoPortfolioData.lots(.quant) }
    private var etfs: [DemoHolding] { quant.filter { $0.kind == "ETF" } }
    private var stocks: [DemoHolding] { quant.filter { $0.kind == "股票" } }
    var body: some View {
        DesktopPageScrollView {
            VStack(spacing: 20) {
                if demo.scope == .personal {
                    ContentUnavailableView("个人账户没有量化策略", systemImage: "person.crop.circle", description: Text("切换到全部或量化范围，查看策略工作台。"))
                        .frame(height: 370)
                } else {
                    // A notice about the quant side waiting for 确认已查看, in its own words (never a made-up reason).
                    if let notice = demo.pendingCritical.first(where: { $0.owner != .personal }) {
                        HStack(spacing: 14) {
                            Image(systemName: "exclamationmark.shield").font(.title2).foregroundStyle(DesktopTheme.orange)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(notice.title).font(.system(size: 13, weight: .semibold))
                                Text(notice.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Button("确认已查看") { demo.acknowledged.insert(notice.id); demo.read.insert(notice.id) }
                                .buttonStyle(.glass).controlSize(.small)
                        }.padding(20).background(DesktopTheme.orange.opacity(0.08), in: DesktopTheme.surfaceShape)
                    }
                    workspace
                }
            }
        }.scrollIndicators(.hidden)
            .closesForPush($showDetails)
            .sheet(isPresented: $showDetails) { DesktopSheetContainer(title: "量化策略") { DemoStrategyDetail() } }
    }
    /// The quant workspace: metrics, the two strategies, the net value, models and run status.
    @ViewBuilder private var workspace: some View {
        HStack(spacing: 16) {
            DesktopMetricCard(title: "量化总资产", value: DesktopTheme.money(DemoPortfolioData.total(.quant)), detail: "持仓 + 策略现金", icon: "cpu")
            DesktopMetricCard(title: "策略累计收益", value: DesktopTheme.signedMoney(DemoPortfolioData.pnl(.quant)), detail: DesktopTheme.percent(DemoPortfolioData.pnl(.quant), of: DemoPortfolioData.principal(.quant)), icon: "arrow.up.right", tint: DesktopTheme.green)
            DesktopMetricCard(title: "策略可用现金", value: DesktopTheme.money(DemoPortfolioData.cash(.quant)), detail: "预留资金", icon: "banknote", tint: DesktopTheme.orange)
        }
        HStack(spacing: 20) {
            strategyCard(title: "核心 ETF 趋势", caption: "CORE / TREND FOLLOWING", holdings: etfs, icon: "square.stack.3d.up", tint: DesktopTheme.blue)
            strategyCard(title: "量化选股", caption: "ALPHA / STOCK SELECTION", holdings: stocks, icon: "sparkles", tint: .purple)
        }
        DesktopCard {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    DesktopSectionTitle(title: "策略净值", subtitle: "合并策略组合 · 近 30 个交易日")
                    Spacer()
                    DesktopPill(text: "Alpha v3")
                }
                // The built-in net value (never divided by a zero principal).
                let principal = DemoPortfolioData.principal(.quant)
                Chart(DemoPortfolioData.points(.quant)) { point in
                    LineMark(x: .value("日期", point.date), y: .value("净值", principal != 0 ? point.equity / principal : 1))
                        .foregroundStyle(DesktopTheme.blue).lineStyle(StrokeStyle(lineWidth: 2.3)).interpolationMethod(.catmullRom)
                }.chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
                    .frame(height: 240)
            }
        }
        HStack(alignment: .top, spacing: 20) {
            DesktopCard {
                VStack(alignment: .leading, spacing: 22) {
                    DesktopSectionTitle(title: "模型观察", subtitle: "冠军与影子挑战者")
                    modelRow("Alpha v3", detail: "当前冠军 · 展示模型", badge: "CHAMPION", tint: DesktopTheme.blue)
                    Divider().opacity(0.5)
                    modelRow("Alpha v4", detail: "影子观察 · 第 12 天", badge: "SHADOW", tint: .purple)
                    Text("挑战者只比较结果，不自动替换冠军。").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            DesktopCard {
                VStack(alignment: .leading, spacing: 22) {
                    DesktopSectionTitle(title: "运行状态")
                    LabeledContent("最近检查", value: "10:32 · 完成")
                    LabeledContent("数据延迟", value: "2 分钟")
                    LabeledContent("失败任务", value: "0")
                    Button("查看完整策略详情 ↗") { showDetails = true }.buttonStyle(.glass).foregroundStyle(.primary)
                }.font(.system(size: 12))
            }
        }
    }
    private func strategyCard(title: String, caption: String, holdings: [DemoHolding], icon: String, tint: Color) -> some View {
        let total = holdings.reduce(0) { $0 + $1.value }
        let pnl = holdings.reduce(0) { $0 + $1.pnl }
        return DesktopCard {
            VStack(alignment: .leading, spacing: 21) {
                HStack {
                    Image(systemName: icon).font(.system(size: 20)).foregroundStyle(tint)
                    Spacer()
                    DesktopPill(text: "监控中", color: tint)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(caption).font(.system(size: 9, weight: .medium)).tracking(1.4).foregroundStyle(.secondary)
                    Text(title).font(.system(size: 19, weight: .semibold))
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(DesktopTheme.money(total)).font(.system(size: 32, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(DesktopTheme.signedMoney(pnl)).font(.system(size: 12)).foregroundStyle(DesktopTheme.pnlColor(pnl))
                }
                HStack(spacing: 7) { ForEach(holdings) { DesktopPill(text: $0.symbol, color: tint) } }
            }
        }
    }
    private func modelRow(_ title: String, detail: String, badge: String, tint: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            DesktopPill(text: badge, color: tint)
        }
    }
}
