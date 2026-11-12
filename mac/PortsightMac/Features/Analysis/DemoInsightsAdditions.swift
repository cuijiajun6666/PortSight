import SwiftUI
import Charts
import PortSightKit
struct DemoInsightsAdditions: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @State private var symbol = ""
    @State private var hint = ""
    var body: some View {
        VStack(spacing: 16) {
            HStack { Text("模型与复盘").font(.title3.bold()); Spacer() }
            NavigationLink { DemoReportDetail() } label: {
                DemoCard(title: "收益复盘", icon: "chart.xyaxis.line") {
                    HStack { Text("日报 / 周报 / 月报"); Spacer(); Image(systemName: "chevron.right") }
                    Text("账户与基准、回撤、换手和成本").font(.caption).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain)
            DemoCard(title: "自选与持仓建议", icon: "star") {
                HStack {
                    TextField("添加股票代码", text: $symbol).autocorrectionDisabled()
                    Button("添加") {
                        let value = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        guard value.range(of: "^[A-Z][A-Z0-9.\\-]{0,11}$", options: .regularExpression) != nil else { hint = "请输入股票代码，例如 MSFT"; return }
                        if !demo.watchlist.contains(value) { demo.watchlist.append(value) }
                        symbol = ""; hint = ""
                    }
                }
                if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(.orange) }
                ForEach(demo.watchlist, id: \.self) { value in
                    HStack {
                        NavigationLink { DemoAdviceDetail(symbol: value) } label: {
                            HStack { Text(value).font(.subheadline.weight(.semibold)); Spacer(); Text("评分 82").foregroundStyle(.secondary); Image(systemName: "chevron.right").font(.caption) }
                        }.buttonStyle(.plain)
                        Button { demo.watchlist.removeAll { $0 == value } } label: { Image(systemName: "minus.circle").foregroundStyle(.secondary) }.accessibilityLabel("移除 " + value)
                    }.padding(.vertical, 5)
                }
                Text("新添加的代码展示统一模板，不生成真实预测。").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal).padding(.bottom, 30)
    }
}
