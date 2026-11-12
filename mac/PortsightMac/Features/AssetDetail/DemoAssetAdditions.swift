import SwiftUI
import Charts
import PortSightKit
struct DemoAssetAdditions: View {
    @EnvironmentObject private var demo: PortfolioDemo
    let symbol: String
    private var lots: [DemoHolding] { demo.lots(demo.scope).filter { $0.symbol == symbol } }
    var body: some View {
        VStack(spacing: 16) {
            DemoCard(title: "持仓归属", icon: "person.2") {
                DemoOwnershipLabel(symbol: symbol)
                ForEach(lots) { lot in
                    HStack { Text(lot.owner.rawValue); Spacer(); Text(demoMoney(lot.value)); Text("盈亏 " + demoMoney(lot.pnl)).foregroundStyle(lot.pnl >= 0 ? .green : .red) }.font(.subheadline)
                }
                Text("参考模型后手动买入，仍计入个人持仓。").font(.caption).foregroundStyle(.secondary)
            }
            NavigationLink { DemoAdviceDetail(symbol: symbol) } label: {
                DemoCard(title: "模型建议", icon: "sparkles") {
                    HStack { Text("评分 82 · 较上次 +4"); Spacer(); Image(systemName: "chevron.right") }
                    Text("查看 20/60 天区间、止盈止损、加减仓条件和近期事件").font(.caption).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain)
            DemoCard(title: "相关交易", icon: "clock") {
                let entries = ibkrEntries
                let rows = builtInRows
                if entries.isEmpty && rows.isEmpty {
                    Text("暂无这项资产的交易记录").foregroundStyle(.secondary)
                }
                ibkrTrades(entries)
                ForEach(rows) { DemoActivityRow(item: $0) }
            }
        }
    }

    /// Once paired: the personal IBKR account's orders (folded with their fills), fills, position changes and cash
    /// (dividends…) of this symbol, newest first. Empty before pairing and for the quant account.
    private var ibkrEntries: [IBKRTimelineEntry] {
        guard demo.isLive, demo.scope != .quant else { return [] }
        let ticker = symbol.replacingOccurrences(of: "US.", with: "").uppercased()
        return IBKRActivityList.timeline(IBKRActivityStore.shared.items).filter { $0.symbol?.uppercased() == ticker }
    }

    /// The built-in rows about this symbol: all of them before pairing; once paired the ones Portfolio.activities
    /// still lists next to the IBKR records (the quant account's, and the personal ones while IBKR has none).
    private var builtInRows: [DemoActivity] {
        let builtIn = Set(DemoPortfolioData.activities.map(\.id))
        return demo.activities.filter { (!demo.isLive || builtIn.contains($0.id)) && ($0.title + $0.detail).contains(symbol) }
    }

    /// A click on an IBKR row shows the order's status changes and fills, or the record.
    @ViewBuilder private func ibkrTrades(_ entries: [IBKRTimelineEntry]) -> some View {
        ForEach(entries.prefix(Self.liveLimit)) { entry in
            NavigationLink {
                DesktopIBKREntryDetail(entry: entry)
                    .navigationTitle(DesktopIBKRSelection(entry: entry).title)
            } label: {
                HStack {
                    DemoActivityRow(item: entry.asDemoActivity)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        if entries.count > Self.liveLimit {
            Text("仅显示最近 \(Self.liveLimit) 条，全部记录在「动态」页搜索。").font(.caption).foregroundStyle(.secondary)
        }
    }

    private static let liveLimit = 10
}
