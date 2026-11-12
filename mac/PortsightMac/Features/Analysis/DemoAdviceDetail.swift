import SwiftUI
import Charts
import PortSightKit
struct DemoAdviceDetail: View {
    let symbol: String
    /// The reference price: the held price (IBKR's once paired), else the built-in one, else $100.
    private var price: Double {
        Portfolio.holding(symbol)?.price ?? DemoPortfolioData.holdings.first { $0.symbol == symbol }?.price ?? 100
    }
    private func reference(_ factor: Double) -> String { demoMoney(price * factor) }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack { Text(symbol).font(.largeTitle.bold()); Spacer() }
                DemoCard(title: "模型评分", icon: "sparkles") {
                    HStack(alignment: .firstTextBaseline) { Text("82").font(.system(size: 40, weight: .bold)); Text("/100").foregroundStyle(.secondary); Spacer(); Text("↑ 4").foregroundStyle(.green) }
                    LabeledContent("池内排名", value: "第 12 / 500 · 上升 5 位")
                    Text("Alpha v3 · 模型输出").font(.caption).foregroundStyle(.secondary)
                }
                DemoCard(title: "预期与区间", icon: "chart.line.uptrend.xyaxis") {
                    forecast("未来 20 个交易日", expected: "+3.2%", range: "−6.0% ~ +12.0%")
                    Divider()
                    forecast("未来 60 个交易日", expected: "+8.4%", range: "−12.0% ~ +24.0%")
                    Text("80% 预测区间，不能视为保证收益。").font(.caption).foregroundStyle(.secondary)
                }
                DemoCard(title: "价格条件", icon: "flag.2.crossed") {
                    LabeledContent("参考价格", value: reference(1))
                    LabeledContent("止损参考", value: reference(0.92))
                    LabeledContent("止盈参考", value: reference(1.15))
                    LabeledContent("历史先触止盈 / 止损", value: "58% / 27%")
                    LabeledContent("观察期内均未触及", value: "15%")
                }
                DemoCard(title: "仓位与行动条件", icon: "slider.horizontal.3") {
                    Text("加仓：突破观察区间并维持两日，成交量同步增加。")
                    Text("历史胜率：61% · 124 个样本").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("减仓：跌破趋势线，或合并敞口超过预设目标。")
                    Text("历史胜率：56% · 98 个样本").font(.caption).foregroundStyle(.secondary)
                    LabeledContent("建议仓位", value: "5%")
                }
                DemoCard(title: "近期事件", icon: "calendar") {
                    Label("财报 · 未来一周的提醒", systemImage: "doc.text")
                    Label("内部人交易 · 记录待核实", systemImage: "person.text.rectangle")
                    Text("增发、13D 和财报重述也将在此展示。").font(.caption).foregroundStyle(.secondary)
                }
                Text("成本假设为单边 0.10%。建议仅供参考，App 不会下单。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding()
        }.background(DesktopTheme.canvas).navigationTitle("建议详情")
    }
    private func forecast(_ title: String, expected: String, range: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title); Spacer(); Text(expected).foregroundStyle(.green).fontWeight(.semibold) }
            Text("区间 " + range).font(.caption).foregroundStyle(.secondary)
        }
    }
}
