//
//  TerminalStrategiesWorkbench.swift
//  PortSight
//
//  交易 · 策略: the quant workbench (matches the Mac 策略 page). Totals, the protection-check banner,
//  both strategies with their holdings, the combined equity curve, models and run status.
//  Read-only: nothing here changes a strategy, a model or an order.
//

import SwiftUI
import Charts
import PortSightKit

struct TerminalStrategiesWorkbench: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @State private var acknowledgedCount = 0
    @State private var selectedDate: Date?

    // The quant account is not on the relay yet: these are the built-in quant figures, paired or not
    // (demo.*(.quant) is empty once paired). Only the notices below come from the relay.
    private var quant: [DemoHolding] { DemoPortfolioData.lots(.quant) }
    private var etfs: [DemoHolding] { quant.filter { $0.kind == "ETF" } }
    private var stocks: [DemoHolding] { quant.filter { $0.kind == "股票" } }
    private var total: Double { DemoPortfolioData.total(.quant) }
    private var pnl: Double { DemoPortfolioData.pnl(.quant) }
    private var principal: Double { DemoPortfolioData.principal(.quant) }
    private var points: [DemoPoint] { DemoPortfolioData.points(.quant) }
    private var selectedPoint: DemoPoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        PortSightList {
            if demo.scope == .personal {
                ContentUnavailableView {
                    Label("个人账户没有量化策略", systemImage: "person.crop.circle")
                } description: {
                    Text("切换到全部或量化范围，查看策略。")
                } actions: {
                    Button("切换到全部") { withAnimation(.smooth) { demo.scope = .all } }
                        .buttonStyle(.bordered)
                }
                .listRowBackground(Color.clear)
            } else {
                heroSection
                // The quant side's notices only: a personal one (e.g. IBKR re-authorization) has its own place on 总览.
                if let notice = demo.pendingCritical.first(where: { !$0.fromRelay || $0.owner != .personal }) {
                    protectionBanner(notice)
                }
                strategiesSection
                equitySection
                modelsSection
                statusSection
            }
        }
        .terminalPageList()
        .animation(.smooth, value: demo.scope)
        .animation(.smooth, value: demo.pendingCritical.count)
        .sensoryFeedback(.success, trigger: acknowledgedCount)
    }

    // MARK: Sections

    private var heroSection: some View {
        Section {
            TerminalHero(eyebrow: "量化总资产", value: terminalMoney(total), detail: "持仓 + 策略现金") {
                HStack(spacing: 18) {
                    figure("策略累计收益", terminalSignedMoney(pnl) + " · " + TerminalFormat.percent(pnl / max(1, principal)),
                           value: pnl, tint: TerminalStyle.pnl(pnl))
                    figure("策略可用现金", terminalMoney(DemoPortfolioData.cash(.quant)),
                           value: DemoPortfolioData.cash(.quant), tint: .primary)
                }
            }
            .terminalHeroRow()
        }
    }

    private func figure(_ title: String, _ text: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                .monospacedDigit().contentTransition(.numericText(value: value))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    private func protectionBanner(_ notice: DemoNotice) -> some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.shield").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    // A relay notice says what happened itself; the built-in one keeps its text.
                    Text(notice.fromRelay ? notice.title : "保护检查中").font(.subheadline.weight(.semibold))
                    Text(notice.fromRelay ? notice.detail : "报价异常，相关调仓已暂缓。").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            Button("确认已查看") {
                demo.acknowledged.insert(notice.id)
                demo.read.insert(notice.id)
                acknowledgedCount += 1
            }
        } footer: {
            Text("确认后提示消失，不会修改任何策略或交易状态。")
        }
        .listRowBackground(Color.orange.opacity(0.1))
    }

    private var strategiesSection: some View {
        Section("策略") {
            NavigationLink { DemoStrategyDetail().portSightBackdrop() } label: {
                TerminalStrategyRow(title: "核心 ETF 趋势", caption: "CORE / TREND FOLLOWING", holdings: etfs,
                                    icon: "square.stack.3d.up", tint: .blue)
            }
            NavigationLink { DemoStrategyDetail().portSightBackdrop() } label: {
                TerminalStrategyRow(title: "量化选股", caption: "ALPHA / STOCK SELECTION", holdings: stocks,
                                    icon: "sparkles", tint: .purple)
            }
        }
    }

    private var equitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    let point = selectedPoint ?? points.last
                    let nav = (point?.equity ?? principal) / max(1, principal)
                    Text(nav.formatted(.number.precision(.fractionLength(3))))
                        .font(.title3.weight(.semibold)).monospacedDigit()
                        .contentTransition(.numericText(value: nav))
                    if let point {
                        Text(point.date, format: .dateTime.month().day()).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Alpha v3").font(.caption2.weight(.semibold)).foregroundStyle(.blue)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.blue.opacity(0.12), in: Capsule())
                }
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("日期", point.date), y: .value("净值", point.equity / max(1, principal)))
                            .foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.catmullRom)
                    }
                    if let selectedPoint {
                        RuleMark(x: .value("日期", selectedPoint.date)).foregroundStyle(.secondary.opacity(0.4))
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month().day())
                } }
                .frame(height: 200)
            }
            .padding(.vertical, 6)
            .animation(.smooth(duration: 0.2), value: selectedPoint?.id)
        } header: {
            Text("策略净值")
        } footer: {
            Text("合并策略组合 · 近 30 个交易日")
        }
    }

    private var modelsSection: some View {
        Section {
            modelRow("Alpha v3", detail: "当前冠军", badge: "CHAMPION", tint: .blue)
            modelRow("Alpha v4", detail: "影子观察 · 第 12 天", badge: "SHADOW", tint: .purple)
        } header: {
            Text("模型观察")
        } footer: {
            Text("挑战者只比较结果，不自动替换冠军。")
        }
    }

    private func modelRow(_ title: String, detail: String, badge: String, tint: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(badge).font(.caption2.weight(.semibold)).foregroundStyle(tint)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(tint.opacity(0.12), in: Capsule())
        }
        .accessibilityElement(children: .combine)
    }

    private var statusSection: some View {
        Section("运行状态") {
            LabeledContent("最近检查", value: "10:32 · 完成")
            LabeledContent("数据延迟", value: "2 分钟")
            LabeledContent("失败任务", value: "0")
            NavigationLink("完整策略详情") { DemoStrategyDetail().portSightBackdrop() }
        }
        .monospacedDigit()
    }
}

/// One strategy: value, P&L and the symbols it holds.
struct TerminalStrategyRow: View {
    let title: String
    let caption: String
    let holdings: [DemoHolding]
    let icon: String
    let tint: Color

    private var total: Double { holdings.reduce(0) { $0 + $1.value } }
    private var pnl: Double { holdings.reduce(0) { $0 + $1.pnl } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(tint).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(caption).font(.caption2.weight(.medium)).tracking(1).foregroundStyle(.secondary)
                    Text(title).font(.headline)
                }
                Spacer()
                Label("监控中", systemImage: "eye").font(.caption2.weight(.medium)).foregroundStyle(tint)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(terminalMoney(total)).font(.title2.weight(.semibold)).fontDesign(.rounded)
                    .monospacedDigit().contentTransition(.numericText(value: total))
                Spacer()
                Text(terminalSignedMoney(pnl)).font(.subheadline).foregroundStyle(TerminalStyle.pnl(pnl))
                    .monospacedDigit().contentTransition(.numericText(value: pnl))
            }
            HStack(spacing: 6) {
                ForEach(holdings) { holding in
                    Text(holding.symbol).font(.caption2.weight(.semibold)).foregroundStyle(tint)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(tint.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
