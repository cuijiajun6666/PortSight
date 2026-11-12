//
//  分时图.swift
//  PortSight
//
//  Created by Chris Cui on 17/5/2026.
//

import Charts
import SwiftUI
import Foundation
import Combine
import PortSightKit

struct IntradayLineChart: View {
    let symbol: String
    @ObservedObject var marketVM: MarketStatusViewModel
    var height: CGFloat = 58
    var refreshesOnAppear = true
    var maximumPointCount: Int?
    var initialRefreshDelay: Double = 0

    @StateObject private var vm = IntradayPriceViewModel()

    var body: some View {
        IntradaySparklineChart(
            points: vm.points,
            height: height,
            maximumPointCount: maximumPointCount
        )
            .overlay {
                if vm.points.isEmpty && refreshesOnAppear {
                    ProgressView()
                        .opacity(vm.isLoading ? 1 : 0)
                }
            }
            .task(id: symbol) {
                vm.loadCache(symbol: symbol)

                if refreshesOnAppear {
                    if initialRefreshDelay > 0 {
                        try? await Task.sleep(for: .seconds(initialRefreshDelay))
                        guard !Task.isCancelled else { return }
                    }
                    vm.start(symbol: symbol)
                }
            }
            .onChange(of: marketVM.session) { oldSession, newSession in
                // The session follows the clock in demo mode: nothing to re-fetch when it opens.
                if DemoPortfolioData.enabled { return }
                guard oldSession != .regular, newSession == .regular else { return }
                vm.resetForOpenSession(symbol: symbol)
            }
            .onDisappear {
                vm.stop()
            }
    }

}

struct IntradaySparklineChart: View {
    let points: [IntradayPricePoint]
    var height: CGFloat = 58
    var maximumPointCount: Int?
    var tintColor: Color?

    private var renderedPoints: [IntradayPricePoint] {
        guard let maximumPointCount,
              maximumPointCount > 2,
              points.count > maximumPointCount else {
            return points
        }

        let step = Double(points.count - 1) / Double(maximumPointCount - 1)
        var indices = Set<Int>()

        for offset in 0..<maximumPointCount {
            indices.insert(Int((Double(offset) * step).rounded()))
        }

        return indices.sorted().map { points[$0] }
    }

    private var lineColor: Color {
        if let tintColor {
            return tintColor
        }

        guard let first = renderedPoints.first?.curPrice,
              let last = renderedPoints.last?.curPrice else {
            return .secondary
        }

        return last >= first ? .green : .red
    }

    private var yDomain: ClosedRange<Double> {
        let prices = renderedPoints.map(\.curPrice)
        guard let minPrice = prices.min(),
              let maxPrice = prices.max() else {
            return 0...1
        }

        guard minPrice != maxPrice else {
            let padding = max(abs(minPrice) * 0.002, 0.01)
            return (minPrice - padding)...(maxPrice + padding)
        }

        let padding = max((maxPrice - minPrice) * 0.08, 0.01)
        return (minPrice - padding)...(maxPrice + padding)
    }

    private var minPrice: Double {
        renderedPoints.map(\.curPrice).min() ?? 0
    }

    var body: some View {
        Chart(renderedPoints) { point in
            if let date = point.date {
                LineMark(
                    x: .value("Time", date),
                    y: .value("Price", point.curPrice)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(lineColor)
                .lineStyle(StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

                AreaMark(
                    x: .value("Time", date),
                    yStart: .value("Min", minPrice),
                    yEnd: .value("Price", point.curPrice)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            lineColor.opacity(0.3),
                            .clear
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
        .frame(height: height)
    }
}
