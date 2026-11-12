import SwiftUI
import Charts
import PortSightKit

/// 交易 · 线路: every line's mode, last run, stage pipeline and sub-strategies.
struct DesktopTradingLinesView: View {
    /// Line to scroll to when the page opens (e.g. from a strategy row on 总览); nil starts at the top.
    let initialLineID: String?

    init(initialLineID: String? = nil) {
        self.initialLineID = initialLineID
    }

    /// The built-in lines, paired or not: the relay has no source for the lines' status and results yet.
    var body: some View {
        ScrollViewReader { proxy in
            DesktopFullPage {
                DesktopPageHeader(eyebrow: "交易线路", title: "\(DemoTerminalData.lines.count) 条线路运行中",
                                  detail: "App 只看不下单；下单程序只在 Mac mini 上运行。")
                ForEach(Array(DemoTerminalData.lines.enumerated()), id: \.element.id) { index, line in
                    DesktopPageSection(title: line.title, subtitle: line.caption, showsDivider: index > 0) {
                        lineBody(line)
                    } trailing: {
                        HStack(spacing: 8) {
                            DesktopStatusDot(color: DesktopStatus.color(line.state))
                            Text(line.state.title).font(.system(size: 11)).foregroundStyle(.secondary)
                            DesktopModePill(mode: line.mode)
                        }
                    }
                    .id(line.id)
                }
            }
            .onAppear { scroll(proxy, to: initialLineID, animated: false) }
            .onChange(of: initialLineID) { _, id in scroll(proxy, to: id, animated: true) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: String?, animated: Bool) {
        guard let id, DemoTerminalData.lines.contains(where: { $0.id == id }) else { return }
        // Wait one run-loop turn so the sections are laid out before scrolling.
        DispatchQueue.main.async {
            if animated {
                withAnimation(.smooth(duration: 0.3)) { proxy.scrollTo(id, anchor: .top) }
            } else {
                proxy.scrollTo(id, anchor: .top)
            }
        }
    }

    @ViewBuilder private func lineBody(_ line: TradingLine) -> some View {
        HStack(spacing: 28) {
            DesktopStat(label: "上次运行", value: TerminalFormat.relative(line.lastRun), detail: line.lastResult)
            DesktopStat(label: "下次运行", value: line.nextRun.map { ServerDates.clock($0) } ?? "—", detail: line.mode.detail)
            DesktopStat(label: "缩放", value: line.scale.formatted(.number.precision(.fractionLength(1))), detail: "账户风控给出的比例")
            VStack(alignment: .leading, spacing: 8) {
                Text("上线检验").font(.system(size: 11)).foregroundStyle(.secondary)
                Gauge(value: line.readiness) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(line.checksPassed)/\(line.checksTotal)").monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(DesktopTheme.blue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        DesktopStagePipeline(stages: line.stages)
        if !line.sleeves.isEmpty {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                GridRow {
                    Text("子策略"); Text("阶段"); Text("权重"); Text("收益")
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
                ForEach(line.sleeves) { sleeve in
                    GridRow {
                        Text(sleeve.name).font(.system(size: 12, weight: .medium))
                        DesktopModePill(mode: sleeve.mode)
                        HStack(spacing: 8) {
                            ProgressView(value: sleeve.weight).frame(width: 90).tint(DesktopTheme.blue)
                            Text(TerminalFormat.percent(sleeve.weight, signed: false)).monospacedDigit()
                        }
                        if DesktopLineSeal.isSealed(line) {
                            Text("封存中").foregroundStyle(.secondary)
                                .help("影子账本在前向封存期，收益 \(DesktopLineSeal.opensTitle) 开放")
                        } else {
                            Text(TerminalFormat.percent(sleeve.returnPct)).monospacedDigit()
                                .foregroundStyle(DesktopTheme.pnlColor(sleeve.returnPct))
                                .contentTransition(.numericText(value: sleeve.returnPct))
                        }
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }
}

/// Stage chain: each stage a dot and name, linked by hairlines; the note sits underneath.
struct DesktopStagePipeline: View {
    let stages: [TradingStage]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 0) {
                        Circle()
                            .strokeBorder(DesktopStatus.color(stage.state), lineWidth: 2)
                            .background(Circle().fill(stage.state == .ok ? DesktopStatus.color(stage.state) : .clear))
                            .frame(width: 12, height: 12)
                        if index < stages.count - 1 {
                            Rectangle().fill(.separator).frame(height: 1).padding(.horizontal, 6)
                        }
                    }
                    Text(stage.name).font(.system(size: 12, weight: .semibold))
                    Text(stage.note).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(stage.state.title)
            }
        }
    }
}

/// 交易 · 复盘: daily / weekly report for one line, equity against its benchmark, then against its backtest.
/// A shadow ledger in the crypto forward seal shows status and checks only.
struct DesktopTradingReportsView: View {
    /// Line shown when the page opens (e.g. from a strategy row on 总览); nil or unknown picks the first line.
    let initialLineID: String?

    @State private var lineID: String
    @State private var weekly = true
    @State private var hovered: Date?

    init(initialLineID: String? = nil) {
        self.initialLineID = initialLineID
        _lineID = State(initialValue: Self.validID(initialLineID) ?? DemoTerminalData.lines.first?.id ?? "")
    }

    private static func validID(_ id: String?) -> String? {
        guard let id, DemoTerminalData.lines.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    private var line: TradingLine { DemoTerminalData.lines.first { $0.id == lineID } ?? DemoTerminalData.lines[0] }
    private var report: TradingReport { weekly ? line.weekly : line.daily }
    private var sealed: Bool { DesktopLineSeal.isSealed(line) }

    /// The built-in reports, paired or not: the relay has no source for the returns, benchmark and net value yet.
    var body: some View {
        DesktopFullPage {
            DesktopPageHeader(eyebrow: line.title + " · " + (weekly ? "周报" : "日报"),
                              title: sealed ? "前向封存中" : TerminalFormat.percent(report.returnPct),
                              detail: sealed ? "影子账本只显示状态和检验，收益 \(DesktopLineSeal.opensTitle) 开放。" : report.summary) {
                HStack(spacing: 12) {
                    DesktopCapsuleMenu(title: "线路", value: line.title, selection: $lineID) {
                        ForEach(DemoTerminalData.lines) { Text($0.title).tag($0.id) }
                    }
                    .labelsHidden().fixedSize()
                    DesktopCapsulePicker(title: "周期", options: [false, true], selection: $weekly) { $0 ? "周报" : "日报" }.labelsHidden().fixedSize()
                }
            }

            if sealed {
                sealedSummary
            } else {
                HStack(spacing: 28) {
                    DesktopStat(label: "收益", value: TerminalFormat.percent(report.returnPct), tint: DesktopTheme.pnlColor(report.returnPct))
                    DesktopStat(label: "基准", value: TerminalFormat.percent(report.benchmarkPct))
                    DesktopStat(label: "超额", value: TerminalFormat.percent(report.returnPct - report.benchmarkPct),
                                tint: DesktopTheme.pnlColor(report.returnPct - report.benchmarkPct))
                    DesktopStat(label: "最大回撤", value: TerminalFormat.percent(-report.maxDrawdown))
                    DesktopStat(label: "换手", value: TerminalFormat.percent(report.turnover, signed: false))
                    DesktopStat(label: "成本", value: report.costBps.formatted(.number.precision(.fractionLength(1))) + " bp")
                }

                DesktopPageSection(title: "净值曲线", subtitle: line.mode == .paper ? "模拟盘按比例显示，不与真实账户相加" : "影子阶段的假想净值") {
                    equityChart
                }
            }

            DesktopReportBacktestCompare(line: line)
                .id(line.id)
        }
        .animation(.smooth(duration: 0.25), value: lineID)
        .animation(.smooth(duration: 0.25), value: weekly)
        .onChange(of: initialLineID) { _, id in
            if let id = Self.validID(id) { lineID = id }
        }
    }

    /// Sealed shadow ledger: status, checks and counts only.
    private var sealedSummary: some View {
        HStack(spacing: 28) {
            DesktopStat(label: "状态", value: line.state.title, detail: line.mode.detail)
            DesktopStat(label: "上线检验", value: "\(line.checksPassed)/\(line.checksTotal)", detail: "通过 / 全部")
            DesktopStat(label: "上次运行", value: TerminalFormat.relative(line.lastRun), detail: line.lastResult)
            DesktopStat(label: "子策略", value: "\(line.sleeves.count) 条", detail: "均为影子阶段")
        }
    }

    @ViewBuilder private var equityChart: some View {
        Chart {
            ForEach(report.points) { point in
                LineMark(x: .value("日期", point.date), y: .value("净值", point.equity), series: .value("曲线", "策略"))
                    .foregroundStyle(DesktopTheme.blue).lineStyle(StrokeStyle(lineWidth: 2.2)).interpolationMethod(.catmullRom)
                LineMark(x: .value("日期", point.date), y: .value("净值", point.benchmark), series: .value("曲线", "基准"))
                    .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1.4, dash: [4, 3])).interpolationMethod(.catmullRom)
            }
            if let hovered, let point = report.points.min(by: { abs($0.date.timeIntervalSince(hovered)) < abs($1.date.timeIntervalSince(hovered)) }) {
                RuleMark(x: .value("日期", point.date))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, alignment: .leading) {
                        Text(point.date.formatted(.dateTime.month().day()) + "  " + TerminalFormat.percent(point.equity - 1))
                            .font(.system(size: 11, weight: .medium)).monospacedDigit()
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.regularMaterial, in: Capsule())
                    }
            }
        }
        .chartXSelection(value: $hovered)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis { AxisMarks { value in
            AxisGridLine().foregroundStyle(.separator)
            AxisValueLabel { if let v = value.as(Double.self) { Text(TerminalFormat.percent(v - 1)) } }
        } }
        .chartLegend(.hidden)
        .frame(height: 300)
        HStack(spacing: 18) {
            Label("策略", systemImage: "line.diagonal").foregroundStyle(DesktopTheme.blue)
            Label("基准", systemImage: "line.diagonal").foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
    }
}
