import SwiftUI
import Charts
import PortSightKit
struct DemoStrategyDetail: View {
    /// The built-in strategies, paired or not: the relay has no source for the quant account yet.
    var body: some View {
        List {
            Section("策略组合") {
                LabeledContent("核心 ETF 趋势", value: demoMoney(37950))
                LabeledContent("量化选股", value: demoMoney(4200))
                LabeledContent("策略现金", value: demoMoney(13000))
                LabeledContent("执行状态", value: "保护检查中")
            }
            Section("模型") {
                LabeledContent("冠军模型", value: "Alpha v3")
                LabeledContent("影子挑战者", value: "Alpha v4 · 观察第 12 天")
                LabeledContent("最新漂移提醒", value: "成交量特征分布变化 · 低等级")
                Text("挑战者只比较结果，不自动替换冠军。").font(.caption).foregroundStyle(.secondary)
            }
            Section("运行记录") {
                LabeledContent("最近运行", value: "10:32 · 完成")
                LabeledContent("数据新鲜度", value: "2 分钟前")
                LabeledContent("死信数量", value: "0")
                Text("此页面只展示监控状态，不提供交易、策略或风险参数操作。").font(.caption)
            }
        }.navigationTitle("量化策略")
    }
}
