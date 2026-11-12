import SwiftUI
import Charts
import PortSightKit
struct DemoActivityDetail: View {
    let item: DemoActivity
    /// A real IBKR record (paired, not one of the built-in rows).
    private var isIBKR: Bool { Portfolio.isLive && !DemoPortfolioData.activities.contains { $0.id == item.id } }
    var body: some View {
        List {
            LabeledContent("事件", value: item.title)
            LabeledContent("来源", value: item.owner.rawValue)
            LabeledContent("时间", value: item.time)
            if let amount = item.amount { LabeledContent("金额", value: demoMoney(amount)) }
            Text(item.detail)
            // Once paired the personal rows are the IBKR account's own records (Portfolio.activities); the built-in
            // quant / shared rows keep their usual line.
            Text(isIBKR ? "来自 IBKR 个人账户" : "展示用记录，不对应真实成交或资金操作。")
                .font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("动态详情")
    }
}

