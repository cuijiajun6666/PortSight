//
//  大盘？.swift
//  PortSight
//
//  Created by Chris Cui on 30/4/2026.
//
import SwiftUI
import SwiftData

struct AnalysisView: View {
    @StateObject private var advisorVM = AdvisorViewModel()

    private var overviewMetrics: [AnalysisMetric] {
        [
            AnalysisMetric(
                title: "流动性健康",
                value: advisorVM.portfolio?.marketValue.map { "$\(Self.compactNumber($0))" } ?? "待计算",
                unit: "",
                trend: "组合市值和现金比例后续会一起纳入流动性判断",
                systemImage: "drop.fill",
                tint: .cyan
            ),
            AnalysisMetric(
                title: "风险暴露",
                value: advisorVM.portfolio?.riskScore.map { String(format: "%.1f", $0) } ?? "中等",
                unit: advisorVM.portfolio?.riskScore == nil ? "" : "/100",
                trend: advisorVM.portfolio?.ratingDescription ?? "单一资产和行业波动需要跟踪",
                systemImage: "shield.lefthalf.filled",
                tint: .orange
            ),
            AnalysisMetric(
                title: "分散度",
                value: "\(advisorVM.reportPositions.count)",
                unit: " 项",
                trend: "结合持仓数量、板块权重和相关性判断分散度",
                systemImage: "square.grid.3x3.fill",
                tint: .green
            ),
            AnalysisMetric(
                title: "收益质量",
                value: advisorVM.portfolio?.pnl?.plRatio.map { Self.percent($0) } ?? "待计算",
                unit: "",
                trend: advisorVM.portfolio?.pnl?.totalPL.map { "总盈亏 \(Self.money($0, showSign: true))" } ?? "收益来源、浮盈和回撤会一起评估",
                systemImage: "chart.line.uptrend.xyaxis",
                tint: .blue
            )
        ]
    }

    private let analysisSections: [AnalysisSection] = [
        AnalysisSection(
            title: "资产配置",
            systemImage: "chart.pie.fill",
            tint: .green,
            items: [
                "股票 / ETF / 加密货币 / 现金权重",
                "单一资产最大权重",
                "持仓集中度",
                "现金占比和可用购买力"
            ]
        ),
        AnalysisSection(
            title: "风险结构",
            systemImage: "exclamationmark.triangle.fill",
            tint: .orange,
            items: [
                "组合波动率估计",
                "最大回撤和近期回撤",
                "高波动资产占比",
                "盈利资产和亏损资产比例"
            ]
        ),
        AnalysisSection(
            title: "分散度",
            systemImage: "circle.hexagongrid.fill",
            tint: .mint,
            items: [
                "持仓数量健康度",
                "行业 / 主题 / 资产类别分布",
                "相关性过高的资产组",
                "ETF 与个股重叠风险"
            ]
        ),
        AnalysisSection(
            title: "流动性",
            systemImage: "water.waves",
            tint: .cyan,
            items: [
                "现金覆盖比例",
                "成交活跃度和买卖价差风险",
                "小盘股 / 低流动性资产占比",
                "紧急减仓可执行性"
            ]
        ),
        AnalysisSection(
            title: "估值与动量",
            systemImage: "waveform.path.ecg",
            tint: .purple,
            items: [
                "趋势强弱和均线位置",
                "相对大盘强弱",
                "涨跌幅异常提醒",
                "价格偏离成本区间"
            ]
        ),
    ]

    var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            portfolioBackgroundColor.opacity(0.7),
                            portfolioBackgroundColor.opacity(0.3),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(maxHeight: .infinity)
                .blur(radius: 30)
                .padding(.horizontal, -50)
                .padding(.top, -30)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Portfolio Score")
                            HStack {
                                Text(portfolioScoreText)
                                    .font(.system(size: 40))
                                    .fontWeight(.bold)
                                    .contentTransition(.numericText())
                                    .animation(.easeInOut(duration: 0.25), value: portfolioScoreText)
                                Text(portfolioRatingText)
                                    .font(.system(size: 40))
                                    .fontWeight(.bold)
                                    .foregroundStyle(portfolioRatingColor)
                            }
                        }
                        Spacer()
                    }
                    .padding()
                }
                
                agentRecommendationPlaceholder
                    .padding(.horizontal)
                

                metricGrid
                    .padding(.horizontal)
                    .padding(.top, 16)

                sectionList
                    .padding(.horizontal)
                    .padding(.top, 18)
                
                watchlistPlaceholder
                    .padding(.horizontal)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
            }
            .background(.ultraThinMaterial)
        }
        .task {
            advisorVM.loadCache()

            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await advisorVM.fetchSummary()
            await advisorVM.fetchSuggestions()
            await advisorVM.fetchAlerts()
        }
    }

    private var portfolioScoreText: String {
        guard let score = advisorVM.portfolio?.score else { return "87/100" }
        return "\(Int(score.rounded()))/100"
    }

    private var portfolioRatingText: String {
        advisorVM.portfolio?.ratingLabel ?? "Good"
    }

    private var portfolioRatingColor: Color {
        switch advisorVM.portfolio?.rating {
        case "good", "healthy":
            return .green
        case "watch":
            return .orange
        case "risk", "bad":
            return .red
        default:
            return .green
        }
    }

    private var portfolioBackgroundColor: Color {
        if let rating = advisorVM.portfolio?.rating {
            switch rating {
            case "good":
                return .green
            case "healthy":
                return .mint
            case "watch":
                return .orange
            case "risk":
                return .yellow
            case "bad":
                return .red
            default:
                break
            }
        }

        guard let score = advisorVM.portfolio?.score else {
            return .green
        }

        switch score {
        case 80...100:
            return .green
        case 65..<80:
            return .mint
        case 50..<65:
            return .orange
        case 35..<50:
            return .red
        default:
            return .purple
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(overviewMetrics) { metric in
                AnalysisMetricCard(metric: metric)
            }
        }
    }

    private var sectionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("配置分析")
                .font(.headline)
                .padding(.horizontal, 2)

            ForEach(analysisSections) { section in
                AnalysisSectionCard(section: section)
            }
        }
    }

    private var watchlistPlaceholder: some View {
        let watchItems = advisorVM.reportPositions
            .filter { position in
                let action = position.action ?? ""
                return action == "watch"
                    || action == "add_candidate"
                    || action == "reduce_or_watch"
                    || position.confirmed == false
            }
            .prefix(6)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                    .foregroundStyle(.purple)
                Text("股票观察列表")
                    .font(.headline)
                Spacer()
            }

            if watchItems.isEmpty {
                Text("等待 /advisor/suggestions 返回观察中的股票。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(watchItems)) { position in
                    AnalysisWatchRow(position: position)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30))
    }

    private var agentRecommendationPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "apple.intelligence")
                    .foregroundStyle(.indigo)
                Text("智能建议")
                    .font(.headline)
                Spacer()
            }

            Text(advisorVM.portfolio?.suggestion ?? "基于当前资产配置、实时行情、持仓盈亏、订单和风险指标生成组合级建议。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                AnalysisRecommendationRow(
                    title: "组合结论",
                    text: advisorVM.portfolio?.ratingDescription ?? "当前组合整体健康，但收益来源偏集中，建议继续观察前 5 大持仓权重。",
                    systemImage: "checkmark.seal.fill",
                    tint: portfolioRatingColor
                )

                AnalysisRecommendationRow(
                    title: "风险提醒",
                    text: advisorVM.portfolio?.reasons?.first ?? "单一资产和高波动持仓可能放大回撤，若盘中波动继续扩大，需要降低集中风险。",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange
                )

                AnalysisRecommendationRow(
                    title: "盈亏状态",
                    text: portfolioPnLText,
                    systemImage: "arrow.triangle.branch",
                    tint: .blue
                )

                AnalysisRecommendationRow(
                    title: "提醒",
                    text: advisorVM.alerts.first?.suggestion ?? "跟踪异常涨跌幅、跌破成本区间、成交量放大和订单执行后的组合变化。",
                    systemImage: "eye.fill",
                    tint: .purple
                )
            }
        }
        .padding()
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30))
    }

    private var portfolioPnLText: String {
        guard let pnl = advisorVM.portfolio?.pnl else {
            return "等待后端返回已实现盈亏、未实现盈亏和组合收益率。"
        }

        let total = Self.money(pnl.totalPL ?? 0, showSign: true)
        let unrealized = Self.money(pnl.unrealizedPL ?? 0, showSign: true)
        let ratio = Self.percent(pnl.plRatio ?? 0)
        return "总盈亏 \(total)，未实现 \(unrealized)，收益率 \(ratio)。"
    }

    private static func money(_ value: Double, showSign: Bool = false) -> String {
        let sign = value < 0 ? "-" : (showSign ? "+" : "")
        return "\(sign)$\(String(format: "%.2f", abs(value)))"
    }

    private static func percent(_ value: Double) -> String {
        "\(value >= 0 ? "+" : "-")\(String(format: "%.2f", abs(value * 100)))%"
    }

    private static func compactNumber(_ value: Double) -> String {
        if abs(value) >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }

        if abs(value) >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }

        return String(format: "%.0f", value)
    }
}

private struct AnalysisMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let unit: String
    let trend: String
    let systemImage: String
    let tint: Color
}

private struct AnalysisSection: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let tint: Color
    let items: [String]
}

private struct AnalysisMetricCard: View {
    let metric: AnalysisMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(metric.title)
                .font(.subheadline.weight(.semibold))
            HStack {
                Image(systemName: metric.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(metric.tint)
                
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(metric.value)
                        .font(.title2.weight(.bold))
                    Text(metric.unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(metric.trend)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30))
    }
}

private struct AnalysisSectionCard: View {
    let section: AnalysisSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: section.systemImage)
                    .foregroundStyle(section.tint)
                Text(section.title)
                    .font(.headline)
                Spacer()
            }

            ForEach(section.items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(section.tint.opacity(0.8))
                        .frame(width: 5, height: 5)
                        .padding(.top, 7)

                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30))
    }
}

private struct AnalysisRecommendationRow: View {
    let title: String
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct AnalysisWatchRow: View {
    let position: AdvisorPosition

    private var symbol: String {
        position.code.split(separator: ".").last.map(String.init) ?? position.code
    }

    private var statusText: String {
        if position.confirmed == false,
           position.tradePlan?.triggerPrice == nil,
           position.action == "watch" {
            return "观察中，指标未确认"
        }

        return actionLabel(position.action)
    }

    private var tint: Color {
        switch position.action {
        case "add_candidate":
            return .green
        case "trim", "reduce_or_watch":
            return .orange
        case "watch":
            return .purple
        default:
            return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(symbol)
                    .font(.subheadline.weight(.bold))

                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)

                Spacer()

                if let riskScore = position.riskScore {
                    Text("风险 \(String(format: "%.1f", riskScore))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(position.suggestion ?? "等待完整 Advisor 报告生成观察理由。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let personality = position.profile?.personality,
               let traits = personality.traits,
               !traits.isEmpty {
                Text(traits.prefix(2).joined(separator: " / "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
    }

    private func actionLabel(_ action: String?) -> String {
        switch action {
        case "add_candidate":
            return "候选观察"
        case "reduce_or_watch":
            return "减仓观察"
        case "watch":
            return "观察中"
        case "trim":
            return "考虑减仓"
        case "hold":
            return "持有"
        default:
            return action ?? "观察"
        }
    }
}

#Preview {
    AnalysisView()
        .modelContainer(for: [Item.self, AssetSnapshotRecord.self, StockLogoRecord.self], inMemory: true)
}
