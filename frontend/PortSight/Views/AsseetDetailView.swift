//
//  Stock.swift
//  PortSight
//
//  Created by Chris Cui on 29/4/2026.
//


import SwiftUI
import SwiftData
import UIKit

// MARK: - View

private struct AssetDetailLogoSnapshot {
    let image: UIImage?
    let featureColor: Color?
}

@MainActor
private enum AssetDetailLogoCache {
    static var snapshots: [String: AssetDetailLogoSnapshot] = [:]
}

struct AssetDetailView: View {
    @StateObject private var quoteVM = QuoteViewModel()
    @StateObject private var advisorVM = AdvisorViewModel()
    @EnvironmentObject var marketVM: MarketStatusViewModel
    @Environment(\.modelContext) private var modelContext
    
    @State private var quoteRefreshTask: Task<Void, Never>?
    @State private var logoLoadTask: Task<Void, Never>?
    @State private var advisorRefreshTask: Task<Void, Never>?
    @State private var logoImage: UIImage?
    @State private var logoGradientColor: Color = .blue
    @State private var hasLoadedLogoSnapshot = false

    let asset: PortfolioAsset

    var body: some View {
        ZStack {
            VStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                logoGradientColor.opacity(0.4),
                                logoGradientColor.opacity(0.1),
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
                Spacer()
            }
            ScrollView {
                VStack(spacing: 20) {
                    
                    // MARK: - Header
                    headerView
                    
                    // MARK: - Holdings Card
                    holdingsCard

                    if asset.type == .stock {
                        advisorCard
                    }
                    
                    
                    
                }
                .padding()
            }
            .background(.ultraThinMaterial)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        OrdersView(symbol: asset.symbol)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.line.text.clipboard")
                                .font(.system(size: 16))
                            Text("订单")
                        }
                    }
                }
            }
            .task(id: asset.symbol) {
                guard asset.type == .stock else { return }

                quoteVM.loadCache(symbol: asset.symbol)
                advisorVM.loadMemorySnapshot()
                advisorVM.loadSymbolCache(symbol: asset.symbol)
                loadLogoSnapshotFromMemoryIfAvailable()

                logoLoadTask?.cancel()
                logoLoadTask = Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    await loadLogoSnapshotIfNeeded()
                }

                advisorRefreshTask?.cancel()
                advisorRefreshTask = Task {
                    try? await Task.sleep(for: .milliseconds(850))
                    guard !Task.isCancelled else { return }
                    await advisorVM.fetchSymbol(symbol: asset.symbol)
                }

                quoteRefreshTask?.cancel()
                quoteRefreshTask = Task {
                    try? await Task.sleep(for: .milliseconds(950))
                    guard !Task.isCancelled else { return }
                    quoteVM.startPolling(symbol: asset.symbol, marketVM: marketVM)
                }
            }
            .onDisappear {
                quoteRefreshTask?.cancel()
                quoteRefreshTask = nil
                logoLoadTask?.cancel()
                logoLoadTask = nil
                advisorRefreshTask?.cancel()
                advisorRefreshTask = nil
                quoteVM.stopPolling()
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        
        VStack(alignment: .leading, spacing: 12) {

            HStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        if let logoImage {
                            Image(uiImage: logoImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 27, height: 27)
                                .clipShape(Circle())
                        }
                        Text(asset.symbol)
                            .font(.system(size: 30))
                            .fontWeight(.bold)
                    }
                    
                    HStack(spacing: 5) {
                        Circle()
                            .frame(width: 7, height: 7)
                            .foregroundStyle(.green)
                        Text("交易中")
                            .font(.system(size: 15))
                    }
                    
                }


                Spacer()
                HStack {
                    Image(systemName: holdingTotalPnL >= 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                        .font(.system(size: 24))
                        .fontWeight(.bold)
                        .foregroundStyle(holdingTotalPnL >= 0 ? .green : .red)
                    VStack(alignment: .leading) {
                        Text("持仓盈亏")
                            .foregroundStyle(.gray)
                            .font(.system(size: 14))
                        
                        let totalPnL = holdingTotalPnL
                        let totalRatio = asset.pnlRatio
                        
                        HStack(spacing: 6) {
                            Text("\(totalPnL >= 0 ? "+" : "")$\(totalPnL, specifier: "%.2f")")
                                .contentTransition(.numericText())
                                .animation(.easeInOut, value: totalPnL)
                            Text("(\(totalRatio >= 0 ? "+" : "")\(totalRatio, specifier: "%.2f")%)")
                                .contentTransition(.numericText())
                                .animation(.easeInOut, value: totalRatio)
                        }
                        .font(.system(size: 17))
                        .fontWeight(.bold)
                        .foregroundStyle(totalPnL >= 0 ? .green : .red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.01)
                    }
                }
                .padding(5)
                .padding(.horizontal, 4)
                .padding(.trailing, 2)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .foregroundStyle(holdingTotalPnL >= 0 ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                        RoundedRectangle(cornerRadius: 20)
                            .foregroundStyle(.ultraThinMaterial)
                            .shadow(radius: 0.7)
                    }
                }
                
                
                //今开最高最低
//                VStack(alignment: .leading) {
//                    HStack(spacing: 0) {
//                        Text("今开: ")
//                            .foregroundStyle(.gray)
//                            .font(.subheadline)
//                        let openPrice = quoteVM.quote(for: asset.symbol)?.open_price ?? 0
//                        Text("\(openPrice, specifier: "%.2f")")
//                            .foregroundStyle(priceColor(openPrice))
//                            .font(.subheadline)
//                            .contentTransition(.numericText())
//                            .animation(.easeInOut, value: openPrice)
//                    }
//                    HStack(spacing: 0) {
//                        Text("最高: ")
//                            .foregroundStyle(.gray)
//                            .font(.subheadline)
//                        let highPrice = quoteVM.quote(for: asset.symbol)?.high_price ?? 0
//                        Text("\(highPrice, specifier: "%.2f")")
//                            .foregroundStyle(priceColor(highPrice))
//                            .font(.subheadline)
//                            .contentTransition(.numericText())
//                            .animation(.easeInOut, value: highPrice)
//                    }
//                    HStack(spacing: 0) {
//                        Text("最低: ")
//                            .foregroundStyle(.gray)
//                            .font(.subheadline)
//                        let lowPrice = quoteVM.quote(for: asset.symbol)?.low_price ?? 0
//                        Text("\(lowPrice, specifier: "%.2f")")
//                            .foregroundStyle(priceColor(lowPrice))
//                            .font(.subheadline)
//                            .contentTransition(.numericText())
//                            .animation(.easeInOut, value: lowPrice)
//                    }
//                }
//                .fontWeight(.bold)
            }
            

            HStack {
                VStack(alignment: .leading) {
                    HStack(alignment: .center, spacing: 8) {
                        HStack(spacing: 5) {
                            //开盘价格
                            Text("$\(displayPrice , specifier: "%.3f")")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundStyle(displayChange >= 0 ? .green : .red)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                                .contentTransition(.numericText())
                                .animation(.easeInOut, value: displayPrice)

                            Image(systemName: displayChange >= 0 ? "arrow.up" : "arrow.down")
                                .fontWeight(.bold)
                                .font(.system(size: 25))
                                .foregroundStyle(displayChange >= 0 ? .green : .red)
                                .contentTransition(.numericText())
                                .animation(.easeInOut, value: displayChange)
                        }
                        .layoutPriority(1)

                        Spacer()
                    }
                    
                    HStack(spacing: 4) {
                        Text("\(displayChange >= 0 ? "+" : "-")$\(abs(displayChange), specifier: "%.3f")")
                                .foregroundStyle(displayChange >= 0 ? .green : .red)
                                .fontWeight(.bold)
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                                .contentTransition(.numericText())
                                .animation(.easeInOut, value: displayChange)
                        Text("(\(displayChangePercent >= 0 ? "+" : "-")\(abs(displayChangePercent), specifier: "%.2f")%)")
                            .foregroundStyle(displayChange >= 0 ? .green : .red)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                            .contentTransition(.numericText())
                            .animation(.easeInOut, value: displayChangePercent)
                    }
                    
                    //非开盘价格
                    if asset.type == .stock {
                        switch marketVM.session {
                        case .pre:
                            sessionBadge(
                                "盘前",
                                price: sessionPrice,
                                change: sessionChange,
                                percent: sessionChangePercent
                            )

                        case .after:
                            sessionBadge(
                                "盘后",
                                price: sessionPrice,
                                change: sessionChange,
                                percent: sessionChangePercent
                            )

                        case .overnight:
                            sessionBadge(
                                "夜盘",
                                price: sessionPrice,
                                change: sessionChange,
                                percent: sessionChangePercent
                            )

                        default:
                            EmptyView()
                        }
                    }
                }
                Spacer()
                if asset.type == .stock {
                    IntradayLineChart(
                        symbol: marketDataSymbol,
                        marketVM: marketVM,
                        initialRefreshDelay: 0.65
                    )
                        .frame(minWidth: 82, idealWidth: 118, maxWidth: 142)
                        .layoutPriority(0)
                }
            }

            
            
            
        }
    }

    private var holdingTotalPnL: Double {
        asset.realizedPnL + asset.unrealizedPnL
    }

    private var marketDataSymbol: String {
        guard asset.type == .stock,
              !asset.symbol.contains(".") else {
            return asset.symbol
        }

        return "US.\(asset.symbol)"
    }

    @ViewBuilder
    private func sessionBadge(
        _ text: String,
        price: Double,
        change: Double,
        percent: Double
    ) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("$\(price, specifier: "%.3f")")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(change >= 0 ? .green : .red)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.25), value: price)

            Text("\(change >= 0 ? "+" : "-")\(abs(change), specifier: "%.2f")")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(change >= 0 ? .green : .red)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.25), value: change)

            Text("(\(percent >= 0 ? "+" : "-")\(abs(percent), specifier: "%.2f")%)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(change >= 0 ? .green : .red)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.25), value: percent)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    // MARK: - Holdings

    private var holdingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {

            VStack(spacing: 16) {
                
                metricsGrid([
                    ("已实现盈亏", asset.realizedPnL, true, true),
                    ("未实现盈亏", asset.unrealizedPnL, true, true),
                    ("持股数量", asset.quantity, false, false),

                    ("持仓成本", asset.avgCost, true, false),
                    ("总成本", asset.quantity * asset.avgCost, true, false),
                    ("市值", asset.marketValue, true, false)
                ])
            }
        }
    }

    private var advisorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "apple.intelligence")
                    .foregroundStyle(.indigo)
                Text("个股智能建议")
                    .font(.headline)
                Spacer()

                if let action = advisorPosition?.action {
                    Text(actionLabel(action))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(actionColor(action))
                }
            }

            if let advisorPosition {
                Text(advisorPosition.suggestion ?? "暂无明确建议，继续观察技术面和组合权重。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    advisorScorePill(
                        title: "风险",
                        value: advisorPosition.riskScore,
                        tint: .orange
                    )
                    advisorScorePill(
                        title: "技术",
                        value: advisorPosition.technicalScore,
                        tint: .blue
                    )
                    advisorScorePill(
                        title: "权重",
                        value: advisorPosition.weight.map { $0 * 100 },
                        suffix: "%",
                        tint: .green
                    )
                }

                ForEach((advisorPosition.reasons ?? []).prefix(3), id: \.self) { reason in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(.secondary.opacity(0.7))
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)

                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let tradePlan = advisorPosition.tradePlan {
                    tradePlanView(tradePlan, position: advisorPosition)
                } else if advisorPosition.confirmed == false,
                          advisorPosition.action == "watch" {
                    advisorObservationView()
                }

                if let personality = advisorPosition.profile?.personality {
                    personalityView(personality)
                }

                if let priceStructure = advisorPosition.priceStructure {
                    priceStructureView(priceStructure)
                }

                if let scoreBreakdown = advisorPosition.scoreBreakdown {
                    scoreBreakdownView(scoreBreakdown)
                }

                if let analysisPoints = advisorPosition.analysisPoints,
                   !analysisPoints.isEmpty {
                    analysisPointsView(analysisPoints)
                }

                if let prediction = advisorPosition.prediction {
                    predictionView(prediction)
                }
            } else {
                Text("等待 /advisor/symbol 返回 \(asset.symbol) 的建议。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Row

    private func metricsGrid(
        _ items: [(title: String, value: Double, isMoney: Bool, showSign: Bool)]
    ) -> some View {

        let columns = [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ]

        return LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: 20
        ) {

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in

                metric(
                    item.title,
                    item.value,
                    isMoney: item.isMoney,
                    showSign: item.showSign
                )
            }
        }
    }
    
    private func row(
        _ title1: String, _ value1: Double,
        isMoney1: Bool = true,
        showSign1: Bool = false,
        _ title2: String, _ value2: Double,
        isMoney2: Bool = true,
        showSign2: Bool = false
    ) -> some View {

        HStack(spacing: 20) {
            metric(title1, value1, isMoney: isMoney1, showSign: showSign1)
            metric(title2, value2, isMoney: isMoney2, showSign: showSign2)
        }
    }
    
    private func metric(
        _ title: String,
        _ value: Double,
        isMoney: Bool = true,
        showSign: Bool = false
    ) -> some View {

        VStack(alignment: .leading, spacing: 4) {

            Text(title)
                .foregroundStyle(.secondary)

            Text(format(value, isMoney: isMoney, showSign: showSign))
                .fontWeight(.semibold)
                .foregroundStyle(color(for: value, isMoney: isMoney, showSign: showSign))
                .contentTransition(.numericText())
                .animation(.easeInOut, value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, -4)
    }
    
    private func format(_ value: Double, isMoney: Bool, showSign: Bool) -> String {
        if isMoney {
            let sign = value < 0 ? "-" : (showSign ? "+" : "")
            let formattedValue = String(format: "%.2f", abs(value))

            if showSign {
                return "\(sign)$\(formattedValue)"
            } else {
                return "\(sign)$\(formattedValue)"
            }
        } else {
            return String(format: "%.2f", value)
        }
    }

    private func color(for value: Double, isMoney: Bool, showSign: Bool) -> Color {
        if !isMoney { return .primary }
        if showSign {
            return value >= 0 ? .green : .red
        } else {
            return .primary
        }
    }

    private var advisorPosition: AdvisorPosition? {
        advisorVM.position(for: asset.symbol)
    }

    private func advisorScorePill(
        title: String,
        value: Double?,
        suffix: String = "",
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value.map { "\(String(format: "%.1f", $0))\(suffix)" } ?? "--")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func tradePlanView(_ tradePlan: AdvisorTradePlan, position: AdvisorPosition) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("交易计划")
                .font(.caption.weight(.semibold))

            Text(tradePlanText(tradePlan, position: position))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func advisorObservationView() -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("交易计划")
                .font(.caption.weight(.semibold))

            Text("观察中，指标未确认。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func personalityView(_ personality: AdvisorPersonality) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("股票性格")
                .font(.caption.weight(.semibold))

            if let type = personality.type {
                Text(type.replacingOccurrences(of: "_", with: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let traits = personality.traits, !traits.isEmpty {
                Text(traits.prefix(3).joined(separator: " / "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let note = personality.strategyNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func priceStructureView(_ structure: AdvisorPriceStructure) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("价格结构")
                    .font(.caption.weight(.semibold))
                Spacer()
                if let score = structure.score {
                    Text(String(format: "%.0f", score))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }

            if let status = structure.status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach((structure.points ?? []).prefix(2), id: \.self) { point in
                Text(point)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func scoreBreakdownView(_ breakdown: AdvisorScoreBreakdown) -> some View {
        HStack(spacing: 10) {
            predictionMetric("趋势", breakdown.trendScore.map { $0 / 100 }, asPercent: true)
            predictionMetric("动量", breakdown.momentumScore.map { $0 / 100 }, asPercent: true)
            predictionMetric("波动风险", breakdown.volatilityRisk.map { $0 / 100 }, asPercent: true)
        }
    }

    private func analysisPointsView(_ points: [AdvisorAnalysisPoint]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("分析要点")
                .font(.caption.weight(.semibold))

            ForEach(points.prefix(3)) { point in
                VStack(alignment: .leading, spacing: 2) {
                    Text(point.label ?? point.category ?? "分析")
                        .font(.caption.weight(.semibold))
                    Text(point.detail ?? point.status ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func predictionView(_ prediction: AdvisorPrediction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                predictionMetric("5日趋势", fiveDayTrendValue(prediction), asPercent: true)
                predictionMetric("20日趋势", prediction.trend20d, asPercent: true)
                predictionMetric("60日趋势", prediction.trend60d, asPercent: true)
            }

            HStack(spacing: 10) {
                predictionMetric("30日波动", prediction.expectedVolatility30d, asPercent: true)
                predictionMetric("回撤", prediction.drawdownFromHigh, asPercent: true)
                if let fiveDay = prediction.expectedByHorizon?["5"] {
                    predictionMetric("5日预期", fiveDay.expectedReturn, asPercent: true)
                }
            }
        }
    }

    private func fiveDayTrendValue(_ prediction: AdvisorPrediction) -> Double? {
        prediction.trend5d ?? prediction.expectedByHorizon?["5"]?.expectedReturn
    }

    private func predictionMetric(_ title: String, _ value: Double?, asPercent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map { asPercent ? percentText($0) : String(format: "%.2f", $0) } ?? "--")
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tradePlanText(_ tradePlan: AdvisorTradePlan, position: AdvisorPosition) -> String {
        let isConfirmed = position.confirmed == true

        if !isConfirmed,
           tradePlan.triggerPrice == nil,
           position.action == "watch" {
            return "观察中，指标未确认。"
        }

        guard isConfirmed, let triggerPrice = tradePlan.triggerPrice else {
            return tradePlan.basis ?? "当前以观察为主，暂无明确买卖触发计划。"
        }

        let trigger = "$\(String(format: "%.2f", triggerPrice))"
        let condition = conditionText(tradePlan.triggerCondition)

        if (tradePlan.sellPercent ?? 0) > 0 {
            let qty = tradePlan.sellQty.map { "，约 \(String(format: "%.0f", $0)) 股" } ?? ""
            return "当价格\(condition) \(trigger) 时，考虑卖出 \(String(format: "%.0f", tradePlan.sellPercent ?? 0))%\(qty)。"
        }

        if (tradePlan.buyPercent ?? 0) > 0 {
            return "当价格\(condition) \(trigger) 时，考虑观察或加仓 \(String(format: "%.0f", tradePlan.buyPercent ?? 0))%。"
        }

        return tradePlan.basis ?? "当前以观察为主，暂无明确买卖触发计划。"
    }

    private func conditionText(_ condition: String?) -> String {
        switch condition {
        case "price_at_or_above":
            return "达到或高于"
        case "price_at_or_below":
            return "达到或低于"
        default:
            return "触发"
        }
    }

    private func actionLabel(_ action: String) -> String {
        switch action {
        case "buy", "add", "add_candidate":
            return "观察买入"
        case "sell", "trim":
            return "考虑减仓"
        case "reduce_or_watch":
            return "减仓观察"
        case "hold":
            return "持有"
        case "watch":
            return "观察中"
        default:
            return action
        }
    }

    private func actionColor(_ action: String) -> Color {
        switch action {
        case "buy", "add", "add_candidate":
            return .green
        case "sell", "trim":
            return .red
        case "reduce_or_watch":
            return .orange
        case "hold":
            return .blue
        case "watch":
            return .secondary
        default:
            return .secondary
        }
    }

    private func percentText(_ value: Double) -> String {
        "\(value >= 0 ? "+" : "-")\(String(format: "%.1f", abs(value * 100)))%"
    }
    
    private func stopQuoteRefresh() {
        quoteRefreshTask?.cancel()
        quoteRefreshTask = nil
    }
    
    private var quote: QuoteResponse? {
        quoteVM.quote(for: asset.symbol)
    }

    private var logoTicker: String {
        asset.symbol.split(separator: ".").last.map(String.init)?.uppercased() ?? asset.symbol.uppercased()
    }

    private var displayPrice: Double {
        if asset.type == .crypto {
            return asset.currentPrice
        }

        let quote = quoteVM.quote(for: asset.symbol)

        return quote?.price ?? asset.currentPrice
    }

    private var prevClosePrice: Double {
        quote?.prev_close_price ?? asset.prevClosePrice
    }

    private var displayChange: Double {
        let quote = quoteVM.quote(for: asset.symbol)
        let prevClose = quote?.prev_close_price ?? asset.prevClosePrice

        return displayPrice - prevClose
    }

    private var displayChangePercent: Double {
        let quote = quoteVM.quote(for: asset.symbol)
        let prevClose = quote?.prev_close_price ?? asset.prevClosePrice

        return prevClose > 0 ? displayChange / prevClose * 100 : 0
    }

    private func priceColor(_ price: Double) -> Color {
        guard price > 0 else { return .primary }
        let prevClose = prevClosePrice
        guard prevClose > 0 else { return .primary }

        if price > prevClose {
            return .green
        } else if price < prevClose {
            return .red
        } else {
            return .primary
        }
    }
    
    private var sessionLabel: String? {
        switch marketVM.session {
        case .pre:
            return "盘前"
        case .after:
            return "盘后"
        case .overnight:
            return "夜盘"
        default:
            return nil
        }
    }

    private var sessionPrice: Double {
        switch marketVM.session {
        case .pre:
            return quote?.pre_price ?? quote?.price ?? asset.currentPrice
        case .after:
            return quote?.after_price ?? quote?.price ?? asset.currentPrice
        case .overnight:
            return quote?.overnight_price ?? quote?.price ?? asset.currentPrice
        default:
            return quote?.price ?? asset.currentPrice
        }
    }

    private var sessionChange: Double {
        let last = quote?.price ?? asset.currentPrice      // last_price
        let current = asset.currentPrice                   // currentPrice
        return current - last
    }

    private var sessionChangePercent: Double {
        let current = asset.currentPrice
        return current > 0 ? sessionChange / current * 100 : 0
    }

    private func loadLogoSnapshotFromMemoryIfAvailable() {
        guard let snapshot = AssetDetailLogoCache.snapshots[logoTicker] else { return }
        logoImage = snapshot.image
        logoGradientColor = snapshot.featureColor ?? .blue
        hasLoadedLogoSnapshot = true
    }

    private func loadLogoSnapshotIfNeeded() async {
        guard asset.type == .stock, !hasLoadedLogoSnapshot else { return }
        hasLoadedLogoSnapshot = true

        do {
            let ticker = logoTicker
            let descriptor = FetchDescriptor<StockLogoRecord>(
                predicate: #Predicate { record in
                    record.ticker == ticker
                }
            )
            guard let record = try modelContext.fetch(descriptor).first else {
                return
            }

            let snapshot = AssetDetailLogoSnapshot(
                image: UIImage(data: record.imageData),
                featureColor: record.featureColor
            )

            AssetDetailLogoCache.snapshots[ticker] = snapshot
            logoImage = snapshot.image
            logoGradientColor = snapshot.featureColor ?? .blue
        } catch {
            print("fetch asset detail logo error:", error.localizedDescription)
        }
    }
}

#if DEBUG
private struct AssetDetailStockPreviewHost: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StockLogoRecord.ticker) private var stockLogoRecords: [StockLogoRecord]

    let asset: PortfolioAsset

    var body: some View {
        AssetDetailView(asset: asset)
            .task(id: asset.symbol) {
                await syncStockLogoRecords(
                    symbols: [asset.symbol],
                    records: stockLogoRecords,
                    modelContext: modelContext
                )
            }
    }
}
#endif

#Preview("Stock Detail") {
    NavigationStack {
        AssetDetailStockPreviewHost(
            asset: PortfolioAsset(
                type: .stock,
                symbol: "AAPL",
                name: "Apple",
                quantity: 10,
                avgCost: 180,
                currentPrice: 196.45,
                prevClosePrice: 193.20,
                marketValue: 1964.50,
                realizedPnL: 0,
                unrealizedPnL: 164.50,
                pnlRatio: 9.14,
                currency: "USD",
                source: "moomoo"
            )
        )
    }
    .environmentObject(MarketStatusViewModel())
    .modelContainer(for: [Item.self, AssetSnapshotRecord.self, StockLogoRecord.self], inMemory: true)
}

#Preview("Crypto Detail") {
    NavigationStack {
        AssetDetailView(
            asset: PortfolioAsset(
                type: .crypto,
                symbol: "BTC",
                name: "Bitcoin",
                quantity: 0.05,
                avgCost: 65000,
                currentPrice: 71000,
                prevClosePrice: 69000,
                marketValue: 3550,
                realizedPnL: 0,
                unrealizedPnL: 300,
                pnlRatio: 9.23,
                currency: "USD",
                source: "okx"
            )
        )
    }
    .environmentObject(MarketStatusViewModel())
    .modelContainer(for: [Item.self, AssetSnapshotRecord.self, StockLogoRecord.self], inMemory: true)
}
