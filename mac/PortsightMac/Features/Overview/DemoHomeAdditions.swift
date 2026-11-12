import SwiftUI
import Charts
import PortSightKit
struct DemoHomeAdditions: View {
    @EnvironmentObject private var demo: PortfolioDemo
    var body: some View {
        VStack(spacing: 14) {
            HStack { Text("Portfolio Overview").font(.title3.bold()); Spacer() }
            if !demo.pendingCritical.isEmpty {
                Button { demo.showNotifications = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("量化保护检查待确认").font(.subheadline.weight(.semibold))
                            Text("点击查看详情").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "chevron.right").font(.caption)
                    }.padding(14).background(.red.opacity(0.07), in: DesktopTheme.surfaceShape)
                }.buttonStyle(.plain)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Once paired the IBKR day's P&L can be a loss: signed, green only when up.
                metric("今日盈亏", value: demo.isLive ? DesktopTheme.signedMoney(demo.dayPnL) : "+" + demoMoney(demo.dayPnL),
                       note: "不含入金与内部划转", positive: !demo.isLive || demo.dayPnL >= 0)
                metric("可用现金", value: demoMoney(demo.cash),
                       note: "占总资产 " + (demo.total != 0 ? demoPercent(demo.cash / demo.total) : "—"))
            }
            if demo.scope == .all {
                DemoCard(title: "资金由谁管理", icon: "square.split.2x2") {
                    managerRow(.personal, color: .blue)
                    managerRow(.quant, color: .orange)
                    Text("同一只股票可以同时由你和量化系统持有，全部视角合并展示。").font(.caption).foregroundStyle(.secondary)
                }
            }
            DemoCard(title: "风险概览", icon: "shield.lefthalf.filled") {
                // The value history: the IBKR account's real curve once read (个人, 全部), else built in.
                let dd = demo.points(demo.scope).map(\.drawdown).max() ?? 0
                HStack { Text("近 30 日最大回撤"); Spacer(); Text(demoPercent(dd)).monospacedDigit() }
                if demo.scope != .personal {
                    ProgressView(value: min(dd, 0.08), total: 0.08).tint(.orange)
                    HStack { Text("风险上限 8%"); Spacer(); Text("剩余 " + demoPercent(max(0, 0.08 - dd))) }.font(.caption).foregroundStyle(.secondary)
                }
                let nvda = demo.holdings.first { $0.symbol == "NVDA" }
                HStack { Text("NVDA 持仓占比"); Spacer(); Text(demo.total != 0 ? demoPercent((nvda?.value ?? 0) / demo.total) : "—") }
                if demo.scope == .all, let split = nvdaSplit {
                    Text(split).font(.caption).foregroundStyle(.secondary)
                }
            }
            if demo.scope != .personal {
                NavigationLink { DemoStrategyDetail() } label: {
                    DemoCard(title: "量化系统", icon: "waveform.path.ecg") {
                        HStack { Label("保护检查中", systemImage: "pause.circle").foregroundStyle(.orange); Spacer(); Image(systemName: "chevron.right") }
                        LabeledContent("最近运行", value: "今天 10:32 · 已完成")
                        LabeledContent("下次计划调仓", value: "下一个交易日 09:35 ET")
                        HStack { Text("冠军模型"); Spacer(); Text("Alpha v3").foregroundStyle(.secondary) }
                        Text("1 个挑战者正在影子运行 · 点击查看策略与模型状态").font(.caption).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
            }
            NavigationLink { DemoReportDetail() } label: {
                DemoCard(title: "每日复盘", icon: "chart.xyaxis.line") {
                    Text(daySummary).font(.subheadline)
                    HStack { Text("查看收益、基准、回撤与成本").font(.caption).foregroundStyle(.secondary); Spacer(); Image(systemName: "arrow.up.right") }
                }
            }.buttonStyle(.plain)
            DemoCard(title: "最近动态", icon: "clock.arrow.circlepath") {
                ForEach(Array(demo.activities.prefix(3))) { item in DemoActivityRow(item: item) }
                Text("不用于推算账户余额").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.top, 24)
    }
    /// 「个人 20 股 + 量化 30 股 = 50 股」: NVDA in both accounts (the IBKR lot once paired, the quant one built in).
    private var nvdaSplit: String? {
        let lots = demo.lots(.all).filter { $0.symbol == "NVDA" }
        let personal = lots.filter { $0.owner == .personal }.reduce(0) { $0 + $1.quantity }
        let quant = lots.filter { $0.owner == .quant }.reduce(0) { $0 + $1.quantity }
        guard personal != 0, quant != 0 else { return nil }
        let shares: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...4))) }
        return "个人 " + shares(personal) + " 股 + 量化 " + shares(quant) + " 股 = " + shares(personal + quant) + " 股"
    }
    /// The day in one line: the built-in sentence before pairing; once paired the same sentence over the figures on
    /// screen (up or down, and the holding that moved the portfolio most that way).
    private var daySummary: String {
        guard demo.isLive else { return "今日组合上涨，主要贡献来自 NVDA；现金比例保持稳定。" }
        let up = demo.dayPnL >= 0
        let lead = up ? demo.holdings.max { $0.dayPnL < $1.dayPnL } : demo.holdings.min { $0.dayPnL < $1.dayPnL }
        return "今日组合" + (up ? "上涨" : "下跌") + (lead.map { "，主要" + (up ? "贡献" : "拖累") + "来自 " + $0.symbol } ?? "")
            + "；现金比例保持稳定。"
    }
    private func metric(_ title: String, value: String, note: String, positive: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(positive ? .green : .primary).contentTransition(.numericText())
            Text(note).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.regularMaterial, in: DesktopTheme.surfaceShape)
    }
    private func managerRow(_ scope: PortfolioScope, color: Color) -> some View {
        Button { withAnimation(.easeInOut) { demo.scope = scope } } label: {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(scope.rawValue)
                Spacer()
                Text(demoMoney(demo.total(scope))).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
            }
        }.buttonStyle(.plain)
    }
}

