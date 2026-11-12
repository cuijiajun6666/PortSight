import SwiftUI
import UniformTypeIdentifiers
import PortSightKit

/// 交易 · 回测: a TradingView-style viewer for backtests the quant system has already run
/// (portsight_backtest_viewer_brief.md). Read-only: it never runs a backtest, never orders and holds no keys.
struct DesktopBacktestView: View {
    @State private var model = BacktestViewerModel()
    @State private var importing = false
    @State private var notesExpanded = false

    var body: some View {
        DesktopFullPage(maxWidth: 1_400, spacing: 26) {
            header
            protocolStrip
            chartSection
            DesktopPageSection(title: "资金曲线与回撤", subtitle: "点击某一天，上方 K 线跳到那天") {
                BacktestEquityChart(model: model)
            }
            DesktopPageSection(title: "指标") {
                BacktestMetricsPanel(run: model.run)
            }
            DesktopPageSection(title: "交易", subtitle: tradesSubtitle) {
                BacktestTradeTable(model: model)
            }
            Text("只读：所有数据来自量化系统导出的结果，App 不跑回测、不下单、不保存交易所密钥。2026-10-22 起的加密数据在前向封存期，不显示收益、净值和交易盈亏。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .closesForPush($importing)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): model.open(directory: url)
            case .failure(let error): model.loadError = error.localizedDescription
            }
        }
        .onChange(of: model.runID) { notesExpanded = false }
    }

    private var tradesSubtitle: String {
        let trades = model.run.trades
        let unpriced = trades.filter { !$0.hasPrices }.count
        return "\(trades.count) 笔" + (unpriced > 0 ? " · \(unpriced) 笔缺开仓或平仓价，图上不画框" : "")
    }

    // MARK: Header

    private var header: some View {
        DesktopPageHeader(eyebrow: "回测", title: model.run.meta.shortTitle, detail: model.run.meta.runID) {
            HStack(spacing: 10) {
                Menu {
                    Picker("回测", selection: Binding(get: { model.runID }, set: { model.changeRun($0) })) {
                        ForEach(model.runSections) { section in
                            Section(section.title) {
                                ForEach(section.runs) { run in Text(run.meta.menuTitle).tag(run.id) }
                            }
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("选择回测", systemImage: "list.bullet.rectangle")
                }
                .fixedSize()
                Menu {
                    Picker("对比", selection: $model.compareID) {
                        Text("不对比").tag(String?.none)
                        ForEach(model.runSections) { section in
                            Section(section.title) {
                                ForEach(section.runs.filter { $0.id != model.runID }) { run in
                                    Text(run.meta.menuTitle).tag(String?.some(run.id))
                                }
                            }
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(model.compareRun.map { "对比 " + $0.meta.shortTitle } ?? "对比", systemImage: "square.on.square")
                }
                .fixedSize()
                Button { importing = true } label: { Label("打开回测目录…", systemImage: "folder") }
                    .help("选一个回测目录（含 meta.json），或放着多个回测的根目录（含 index.json）")
            }
            // Liquid Glass, like the other page headers' buttons.
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
    }

    /// Protocol, data segment, verdict and cost model of the run.
    private var protocolStrip: some View {
        let meta = model.run.meta
        let longCost = meta.costModel.count > 40
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if !meta.verdict.isEmpty {
                        pill(meta.verdictKind.rawValue + " · " + String(meta.verdict.prefix(60)), tint: verdictTint(meta.verdictKind))
                    }
                    if !meta.segment.isEmpty { pill(meta.segmentTitle, tint: DesktopTheme.blue) }
                    if !meta.protocolSHA.isEmpty {
                        pill("协议 " + String(meta.protocolSHA.prefix(8)), tint: .secondary, monospaced: true)
                    }
                    if !meta.costModel.isEmpty && !longCost { pill(meta.costModel, tint: .secondary) }
                    if meta.start > 0 && meta.end > meta.start {
                        pill(BacktestFormat.time(meta.start).prefix(10) + " – " + BacktestFormat.time(meta.end).prefix(10), tint: .secondary)
                    }
                    if model.run.directory == nil { pill("内置样例", tint: DesktopTheme.orange) }
                }
            }
            .scrollIndicators(.never)
            if meta.shortTitle != meta.strategy {
                Text(meta.strategy).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if longCost {
                Text("成本：" + meta.costModel).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let notes = meta.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(notes).font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(notesExpanded ? nil : 3).textSelection(.enabled)
                    if notes.count > 280 {
                        Button(notesExpanded ? "收起说明" : "展开说明") { notesExpanded.toggle() }
                            .buttonStyle(.link).font(.system(size: 11))
                    }
                }
            }
            if let error = model.loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(.red)
            }
        }
    }

    private func verdictTint(_ verdict: BacktestVerdict) -> Color {
        switch verdict {
        case .pass: DesktopTheme.green
        case .fail: .red
        case .reportOnly: .secondary
        }
    }

    private func pill(_ text: some StringProtocol, tint: Color, monospaced: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: monospaced ? .monospaced : .default))
            .foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }

    // MARK: Chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                symbolPicker
                DesktopCapsulePicker(title: "周期", options: model.run.timeframes(model.symbol), selection: Binding(get: { model.timeframe }, set: { model.changeTimeframe($0) })) { $0.title }.fixedSize().labelsHidden()
                Toggle("信号副图", isOn: $model.showsSignals).toggleStyle(.switch).controlSize(.small)
                Spacer()
                legend
                ControlGroup {
                    Button { model.zoom(by: 1.4) } label: { Image(systemName: "minus.magnifyingglass") }
                        .help("缩小")
                    Button { model.zoom(by: 1 / 1.4) } label: { Image(systemName: "plus.magnifyingglass") }
                        .help("放大")
                    Button { model.showAll() } label: { Image(systemName: "arrow.left.and.right") }
                        .help("显示全部")
                }
                .fixedSize()
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 4) {
                    BacktestPriceChart(model: model)
                        .frame(height: 440)
                        .overlay {
                            if model.isLoadingBars {
                                ProgressView("读取 K 线…").controlSize(.small)
                                    .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            } else if model.bars.isEmpty {
                                Text("这个品种在 \(model.timeframe.title) 周期没有导出 K 线")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                    if model.showsSignals {
                        BacktestSignalChart(model: model)
                            .frame(height: 130)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(14)
                .background(DesktopTheme.card, in: DesktopTheme.surfaceShape)
                .overlay { DesktopTheme.surfaceShape.strokeBorder(DesktopTheme.border, lineWidth: 1) }

                if let trade = model.selectedTrade {
                    BacktestTradeDetail(trade: trade) { model.selectedTradeID = nil }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.25), value: model.selectedTradeID)
            .animation(.smooth(duration: 0.25), value: model.showsSignals)

            Text("每笔交易一个框：开仓价以上 / 以下分成盈利区和亏损区，虚线从开仓连到平仓 · 点击框看详情、止损怎么移动和仓位 · 拖动或双指左右滑平移 · 捏合或按住 ⌘ 上下滑缩放")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    /// Every symbol the run traded (or has bars for). A few fit as segments; more become a menu with trade counts.
    @ViewBuilder private var symbolPicker: some View {
        let symbols = model.run.symbols // most traded first
        let selection = Binding(get: { model.symbol }, set: { model.symbol = $0; model.selectedTradeID = nil })
        if symbols.count <= 5 {
            DesktopCapsulePicker(title: "品种", options: symbols, selection: selection) { $0 }.fixedSize().labelsHidden()
        } else {
            let counts = model.tradeCounts
            DesktopCapsuleMenu(title: "品种", value: selection.wrappedValue, selection: selection) {
                ForEach(symbols, id: \.self) { symbol in
                    Text("\(symbol)  ·  \(counts[symbol] ?? 0) 笔").tag(symbol)
                }
            }.fixedSize().labelsHidden()
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            swatch(DesktopTheme.green.opacity(0.35), "盈利区")
            swatch(Color.red.opacity(0.35), "亏损区")
            if model.compareRun != nil { swatch(Color.purple.opacity(0.4), "对比") }
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
    }

    private func swatch(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title)
        }
    }
}
