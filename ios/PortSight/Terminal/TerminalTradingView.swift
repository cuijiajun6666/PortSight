//
//  TerminalTradingView.swift
//  PortSight
//
//  交易 tab: 复盘 · 策略 · 线路. Each line's mode (影子 / 模拟盘 / 实盘), go-live checklist, stages and
//  daily / weekly reports.
//  Read-only: there is no order, cancel or restart control anywhere.
//

import SwiftUI
import Charts
import PortSightKit

/// 交易 pages, in the same order as the Mac app's 交易 tabs.
enum TradingPage: String, CaseIterable, Identifiable {
    case live = "实时", journal = "理由卡", reports = "复盘", strategies = "策略", lines = "线路", backtest = "回测"
    var id: String { rawValue }
}

/// 交易 tab: 实时 · 理由卡 · 复盘 · 策略 · 线路 · 回测, switched from the toolbar's page menu like 资产.
struct TradingTabView: View {
    @Binding var page: TradingPage
    /// false for the unseen copy built after launch (TradingWarmUp): its 实时 page never starts the feed's clock.
    var isActive = true

    var body: some View {
        // Read here so this view updates when the page changes: the 实时 page runs its feed only while in front.
        let current = page
        // Paired or not, the same pages: the quant feed, line reports, strategies, lines and backtests have no source
        // on the relay yet and keep their built-in data; 理由卡 is the relay's own /journal once paired.
        KeptAlivePages(name: "交易页面", page: $page) { item in
            switch item {
            case .live: TerminalLiveTradingView(isActive: isActive && current == .live)
            case .journal: TerminalJournalView()
            case .reports: TerminalReportsView()
            case .strategies:
                NavigationStack {
                    TerminalStrategiesWorkbench()
                        .toolbar { DemoToolbar(showsScope: false) }
                }
            case .lines: TerminalTradingView()
            case .backtest: TerminalBacktestView()
            }
        }
    }
}

/// 交易 · 线路: every line with its mode, last run and go-live checklist.
struct TerminalTradingView: View {
    var body: some View {
        NavigationStack {
            PortSightList {
                Section {
                    TerminalHero(eyebrow: "交易线路", value: "\(DemoTerminalData.lines.count) 条运行中",
                                 detail: "只看不下单，下单程序只在 Mac mini 上运行")
                        .terminalHeroRow()
                }
                Section {
                    ForEach(DemoTerminalData.lines) { line in
                        NavigationLink { TerminalLineDetailView(line: line) } label: { TerminalLineRow(line: line) }
                    }
                } footer: {
                    Text("股票模拟盘名义资金 100 万美元，只显示比例。")
                }
            }
            .terminalPageList()
            .toolbar { DemoToolbar(showsScope: false) }
        }
    }
}

/// 交易 · 复盘: one line's daily or weekly report, equity against its benchmark (matches the Mac 复盘 tab).
struct TerminalReportsView: View {
    @State private var lineID = DemoTerminalData.lines.first?.id ?? ""
    @State private var weekly = true
    @State private var selectedDate: Date?

    private var line: TradingLine { DemoTerminalData.lines.first { $0.id == lineID } ?? DemoTerminalData.lines[0] }
    private var report: TradingReport { weekly ? line.weekly : line.daily }
    private var sealed: Bool { TerminalLineSeal.isSealed(line) }

    var body: some View {
        NavigationStack {
            PortSightList {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("线路", selection: $lineID) {
                            ForEach(DemoTerminalData.lines) { Text($0.title).tag($0.id) }
                        }
                        .pickerStyle(.segmented)
                        Picker("周期", selection: $weekly) {
                            Text("日报").tag(false)
                            Text("周报").tag(true)
                        }
                        .pickerStyle(.segmented)
                        TerminalHero(eyebrow: line.title + " · " + (weekly ? "周报" : "日报"),
                                     value: sealed ? "前向封存中" : TerminalFormat.percent(report.returnPct),
                                     detail: sealed ? "影子账本只显示状态和检验，收益 \(TerminalLineSeal.opensTitle) 开放。" : report.summary)
                            .padding(.top, 4)
                    }
                    .sensoryFeedback(.selection, trigger: lineID)
                    .sensoryFeedback(.selection, trigger: weekly)
                    .terminalHeroRow()
                }

                if sealed {
                    Section {
                        LabeledContent("状态", value: line.state.title)
                        LabeledContent("上线检验", value: "\(line.checksPassed)/\(line.checksTotal)")
                        LabeledContent("上次运行", value: TerminalFormat.relative(line.lastRun))
                        LabeledContent("子策略", value: "\(line.sleeves.count) 条")
                    } header: {
                        Text("状态")
                    } footer: {
                        Label("结果 \(TerminalLineSeal.opensTitle) 开放", systemImage: "lock")
                    }
                    .monospacedDigit()
                } else {
                    reportSections
                }
            }
            .terminalPageList()
            .toolbar { DemoToolbar(showsScope: false) }
            .animation(.smooth, value: lineID)
            .animation(.smooth, value: weekly)
        }
    }

    @ViewBuilder private var reportSections: some View {
                Section {
                    Chart {
                        ForEach(report.points) { point in
                            LineMark(x: .value("日期", point.date), y: .value("净值", point.equity), series: .value("曲线", "策略"))
                                .foregroundStyle(.blue).interpolationMethod(.catmullRom)
                            LineMark(x: .value("日期", point.date), y: .value("净值", point.benchmark), series: .value("曲线", "基准"))
                                .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                                .interpolationMethod(.catmullRom)
                        }
                        if let selectedDate {
                            RuleMark(x: .value("日期", selectedDate)).foregroundStyle(.secondary.opacity(0.4))
                        }
                    }
                    .chartXSelection(value: $selectedDate)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxis { AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel { if let v = value.as(Double.self) { Text(TerminalFormat.percent(v - 1)) } }
                    } }
                    .frame(height: 200)
                    .padding(.vertical, 6)
                } header: {
                    Text("净值曲线")
                } footer: {
                    Text(line.mode == .paper ? "模拟盘按比例显示，不与真实账户相加。" : "影子阶段的假想净值。")
                }

                Section("指标") {
                    LabeledContent("收益") { Text(TerminalFormat.percent(report.returnPct)).foregroundStyle(TerminalStyle.pnl(report.returnPct)) }
                    LabeledContent("基准", value: TerminalFormat.percent(report.benchmarkPct))
                    LabeledContent("超额") {
                        Text(TerminalFormat.percent(report.returnPct - report.benchmarkPct))
                            .foregroundStyle(TerminalStyle.pnl(report.returnPct - report.benchmarkPct))
                    }
                    LabeledContent("最大回撤", value: TerminalFormat.percent(-report.maxDrawdown))
                    LabeledContent("换手", value: TerminalFormat.percent(report.turnover, signed: false))
                    LabeledContent("成本", value: report.costBps.formatted(.number.precision(.fractionLength(1))) + " bp")
                }
                .monospacedDigit()
    }
}

struct TerminalLineDetailView: View {
    let line: TradingLine
    @State private var weekly: Bool
    @State private var selectedDate: Date?

    init(line: TradingLine, showsWeekly: Bool = false) {
        self.line = line
        _weekly = State(initialValue: showsWeekly)
    }

    private var report: TradingReport { weekly ? line.weekly : line.daily }
    private var sealed: Bool { TerminalLineSeal.isSealed(line) }

    var body: some View {
        PortSightList {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(line.caption).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Spacer()
                        TerminalModeBadge(mode: line.mode)
                    }
                    HStack(spacing: 8) {
                        Circle().fill(TerminalStyle.color(line.state)).frame(width: 8, height: 8)
                        Text(line.lastResult).font(.subheadline)
                    }
                }
                LabeledContent("上次运行", value: TerminalFormat.relative(line.lastRun))
                LabeledContent("下次运行", value: line.nextRun.map { ServerDates.clock($0) } ?? "—")
                LabeledContent("缩放", value: line.scale.formatted(.number.precision(.fractionLength(1))))
                LabeledContent("上线检验") {
                    Gauge(value: line.readiness) { EmptyView() } currentValueLabel: {
                        Text("\(line.checksPassed)/\(line.checksTotal)").monospacedDigit()
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(.blue)
                    .scaleEffect(0.8)
                }
            }

            Section("阶段") {
                ForEach(line.stages) { stage in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: stage.state == .ok ? "checkmark.circle.fill" : stage.state == .idle ? "circle.dashed" : "exclamationmark.circle.fill")
                            .foregroundStyle(TerminalStyle.color(stage.state))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stage.name).font(.subheadline.weight(.medium))
                            Text(stage.note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !line.sleeves.isEmpty {
                Section("子策略") {
                    ForEach(line.sleeves) { sleeve in
                        HStack {
                            Text(sleeve.name)
                            TerminalModeBadge(mode: sleeve.mode)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                if sealed {
                                    Text("封存中").foregroundStyle(.secondary)
                                        .accessibilityHint(TerminalLineSeal.note)
                                } else {
                                    Text(TerminalFormat.percent(sleeve.returnPct)).foregroundStyle(TerminalStyle.pnl(sleeve.returnPct))
                                }
                                Text("权重 " + TerminalFormat.percent(sleeve.weight, signed: false)).font(.caption).foregroundStyle(.secondary)
                            }
                            .monospacedDigit()
                        }
                    }
                }
            }

            if sealed {
                Section {
                    Label("前向封存中", systemImage: "lock")
                } header: {
                    Text("复盘")
                } footer: {
                    Text("影子账本只显示状态和检验，结果 \(TerminalLineSeal.opensTitle) 开放。")
                }
            } else {
                reportSection
            }
        }
        .listStyle(.insetGrouped)
        // Pushed from 总览 and 交易 · 线路: on the same backdrop as they are.
        .portSightBackdrop()
        .navigationTitle(line.title)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.smooth, value: weekly)
    }

    private var reportSection: some View {
            Section {
                Picker("周期", selection: $weekly) {
                    Text("日报").tag(false)
                    Text("周报").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                VStack(alignment: .leading, spacing: 12) {
                    Text(report.summary).font(.subheadline)
                    Chart {
                        ForEach(report.points) { point in
                            LineMark(x: .value("日期", point.date), y: .value("净值", point.equity), series: .value("曲线", "策略"))
                                .foregroundStyle(.blue).interpolationMethod(.catmullRom)
                            LineMark(x: .value("日期", point.date), y: .value("净值", point.benchmark), series: .value("曲线", "基准"))
                                .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                                .interpolationMethod(.catmullRom)
                        }
                        if let selectedDate {
                            RuleMark(x: .value("日期", selectedDate)).foregroundStyle(.secondary.opacity(0.4))
                        }
                    }
                    .chartXSelection(value: $selectedDate)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxis { AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel { if let v = value.as(Double.self) { Text(TerminalFormat.percent(v - 1)) } }
                    } }
                    .frame(height: 200)
                }
                .padding(.vertical, 6)
                LabeledContent("收益") { Text(TerminalFormat.percent(report.returnPct)).foregroundStyle(TerminalStyle.pnl(report.returnPct)) }
                LabeledContent("基准", value: TerminalFormat.percent(report.benchmarkPct))
                LabeledContent("最大回撤", value: TerminalFormat.percent(-report.maxDrawdown))
                LabeledContent("换手", value: TerminalFormat.percent(report.turnover, signed: false))
                LabeledContent("成本", value: report.costBps.formatted(.number.precision(.fractionLength(1))) + " bp")
            } header: {
                Text("复盘")
            }
            .monospacedDigit()
    }
}
