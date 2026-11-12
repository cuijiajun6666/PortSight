import SwiftUI
import PortSightKit

struct DesktopPositionsView: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @State private var search = ""
    @State private var kind = "全部"
    @State private var sort = "市值"
    var assetClass: DesktopAssetClass = .all
    let openAsset: (PortfolioAsset) -> Void
    /// Holdings in the selected asset class (美股 / 加密 tabs), before the table's own filters.
    private var classHoldings: [DemoHolding] { demo.holdings.filter { assetClass.contains($0.kind) } }
    private var classTotal: Double { classHoldings.reduce(0) { $0 + $1.value } }
    private var allocation: [AllocationItem] {
        guard assetClass != .all else { return DesktopPortfolioMetrics.allocation(for: demo.scope) }
        return classHoldings.map { AllocationItem(name: $0.symbol, value: $0.value) }.sorted { $0.value > $1.value }
    }
    private var holdings: [DemoHolding] {
        classHoldings.filter {
            (kind == "全部" || $0.kind == kind) && (search.isEmpty || ($0.symbol + $0.name).localizedCaseInsensitiveContains(search))
        }.sorted {
            switch sort {
            case "收益": $0.pnl > $1.pnl
            case "名称": $0.symbol < $1.symbol
            default: $0.value > $1.value
            }
        }
    }
    var body: some View {
        DesktopPageScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 16) {
                    DesktopMetricCard(title: "持仓市值", value: DesktopTheme.money(classTotal), detail: "\(classHoldings.count) 项独立资产", icon: "chart.pie")
                    DesktopMetricCard(title: "持仓浮盈", value: DesktopTheme.signedMoney(classHoldings.reduce(0) { $0 + $1.pnl }), detail: "按加权平均成本计算", icon: "arrow.up.right", tint: DesktopTheme.green)
                    if assetClass == .all {
                        DesktopMetricCard(title: "现金余额", value: DesktopTheme.money(demo.cash), detail: "现金单独计入账户资产", icon: "banknote", tint: DesktopTheme.orange)
                    } else {
                        DesktopMetricCard(title: "今日盈亏", value: DesktopTheme.signedMoney(classHoldings.reduce(0) { $0 + $1.dayPnL }), detail: "按昨日收盘价计算", icon: "sun.max", tint: DesktopTheme.orange)
                    }
                }
                // 「非实时 · 截至 …」 while the IBKR figures are real but not live.
                if let note = demo.liveNote {
                    Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("positions_live_note")
                }
                DesktopCard {
                    VStack(spacing: 24) {
                        HStack {
                            DesktopSectionTitle(title: "资产分布", subtitle: demo.scope.rawValue + "账户" + (assetClass == .usStocks ? " · 美股" : assetClass == .crypto ? " · 加密" : ""))
                            Spacer()
                        }
                        AllocationWeightBar(items: allocation, animationKey: demo.scope.rawValue + "\(assetClass)")
                    }
                }
                DesktopCard {
                    VStack(spacing: 20) {
                        HStack(spacing: 18) {
                            if !assetClass.kinds.isEmpty {
                                DesktopCapsulePicker(title: "类型", options: assetClass.kinds, selection: $kind) { $0 }.labelsHidden()
                            }
                            Spacer()
                            HStack(spacing: 7) {
                                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                TextField("搜索资产", text: $search).textFieldStyle(.plain)
                                    .accessibilityIdentifier("position_search")
                            }.padding(9).frame(width: 170).background(DesktopTheme.canvas, in: RoundedRectangle(cornerRadius: 9))
                            DesktopCapsuleMenu(title: "排序", value: sort, selection: $sort) { ForEach(["市值", "收益", "名称"], id: \.self) { Text($0).tag($0) } }
                        }
                        if holdings.isEmpty {
                            ContentUnavailableView("没有匹配的资产", systemImage: "magnifyingglass", description: Text("尝试其他名称或资产类别。"))
                                .frame(height: 250)
                        } else {
                            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 0) {
                                GridRow {
                                    Text("资产"); Text("现价"); Text("数量 / 成本"); Text("持仓市值"); Text("累计盈亏"); Text("权重")
                                }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.bottom, 12)
                                ForEach(holdings) { holding in
                                    Divider().gridCellUnsizedAxes(.horizontal).opacity(0.5)
                                    GridRow {
                                        HStack(spacing: 10) {
                                            DesktopSymbol(symbol: holding.symbol, crypto: SymbolLogoStore.isCrypto(holding.symbol, kind: holding.kind))
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(holding.symbol).font(.system(size: 13, weight: .semibold))
                                                Text(holding.name).font(.system(size: 10)).foregroundStyle(.secondary)
                                                DemoOwnershipLabel(symbol: holding.symbol)
                                            }
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                        Text(DesktopTheme.money(holding.price)).monospacedDigit()
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(holding.quantity.formatted(.number.precision(.fractionLength(0...4))))
                                            Text(DesktopTheme.money(holding.cost)).font(.system(size: 10)).foregroundStyle(.secondary)
                                        }
                                        Text(DesktopTheme.money(holding.value)).fontWeight(.semibold).monospacedDigit()
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(DesktopTheme.signedMoney(holding.pnl))
                                            Text(DesktopTheme.percent(holding.pnl, of: holding.cost * holding.quantity)).font(.system(size: 10))
                                        }.foregroundStyle(DesktopTheme.pnlColor(holding.pnl))
                                        Text(DesktopTheme.share(holding.value, of: demo.total)).foregroundStyle(.secondary)
                                    }.font(.system(size: 12)).padding(.vertical, 18)
                                        .contentShape(Rectangle()).onTapGesture { openAsset(holding.asset) }
                                        .help("点击查看 " + holding.symbol + " 详情")
                                        .accessibilityElement(children: .combine)
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityAction { openAsset(holding.asset) }
                                }
                            }
                        }
                        HStack {
                            Text("\(holdings.count) 项资产").foregroundStyle(.secondary)
                            Spacer()
                            Text("筛选市值  " + DesktopTheme.money(holdings.reduce(0) { $0 + $1.value })).fontWeight(.medium)
                        }.font(.system(size: 11)).padding(.top, 8)
                    }
                }
            }
        }.scrollIndicators(.hidden)
    }
}
