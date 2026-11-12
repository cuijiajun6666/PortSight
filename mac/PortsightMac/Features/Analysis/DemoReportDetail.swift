import SwiftUI
import Charts
import PortSightKit
struct DemoReportDetail: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @State private var period = "月报"
    @State private var chart = "资产"
    private func shown(_ all: [PortfolioCurvePoint]) -> [PortfolioCurvePoint] {
        period == "日报" ? Array(all.suffix(2)) : period == "周报" ? Array(all.suffix(7)) : all
    }
    /// Return over the period, deposits and withdrawals left out.
    private func performance(_ points: [PortfolioCurvePoint]) -> Double {
        guard let first = points.first, let last = points.last, first.growth != 0 else { return 0 }
        return last.growth / first.growth - 1
    }
    var body: some View {
        // The value curve over the standard range (1月): the real IBKR curve once it has been read, else the built-in
        // one; the benchmark is built in either way (the relay has none).
        let curve = PortfolioCurve(scope: demo.scope)
        let points = shown(curve.points)
        List {
            HStack { Text(demo.scope.rawValue + "复盘");  }
            DesktopCapsulePicker(title: "周期", options: ["日报", "周报", "月报"], selection: $period) { $0 }
            Section {
                Text("\(period)收益 " + demoPercent(performance(points))).font(.title2.bold())
                Text("NVDA 和核心 ETF 提供主要正贡献。入金与内部划转单独记录。").foregroundStyle(.secondary)
                DesktopCapsulePicker(title: "图表", options: ["资产", "收益率"], selection: $chart) { $0 }
                Chart {
                    ForEach(points) { point in
                        let first = points[0]
                        LineMark(x: .value("日期", point.date), y: .value("数值", chart == "资产" ? point.value : Self.change(point.growth, from: first.growth)))
                            .foregroundStyle(by: .value("曲线", "账户"))
                        LineMark(x: .value("日期", point.date), y: .value("数值", chart == "资产" ? point.benchmarkValue : Self.change(point.benchmark, from: first.benchmark)))
                            .foregroundStyle(by: .value("曲线", "基准"))
                    }
                }.frame(height: 210).chartForegroundStyleScale(["账户": Color.blue, "基准": Color.gray])
                Text(caption(isReal: curve.isReal)).font(.caption).foregroundStyle(.secondary)
            }
            Section("风险与成本") {
                LabeledContent("区间最大回撤", value: demoPercent(points.map(\.drawdown).max() ?? 0))
                LabeledContent("换手率", value: "12.4%")
                LabeledContent("交易成本", value: "$8.40")
                Chart(points) { point in
                    AreaMark(x: .value("日期", point.date), y: .value("回撤 %", -point.drawdown * 100)).foregroundStyle(.orange.opacity(0.25))
                    LineMark(x: .value("日期", point.date), y: .value("回撤 %", -point.drawdown * 100)).foregroundStyle(.orange)
                }.frame(height: 110)
            }
        }.navigationTitle("复盘报告")
    }

    private func caption(isReal: Bool) -> String {
        if chart == "资产" { return isReal ? "单位：USD · 出入金计入资产" : "单位：USD · 期间无外部现金流" }
        return isReal ? "区间起点归零 · 出入金不计入收益 · 单位：%" : "区间起点归零 · 单位：%"
    }

    /// Percentage change from `start` (0 when there is no start).
    private static func change(_ value: Double, from start: Double) -> Double {
        start != 0 ? (value / start - 1) * 100 : 0
    }
}
