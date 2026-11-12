//
//  TradeChartModel.swift
//  PortSightKit
//
//  What a K-line chart with trade boxes needs from its page, so one chart draws both a finished backtest
//  (BacktestViewerModel) and an account that is trading right now (LiveViewerModel): candles for a window,
//  the closed trades in it, open positions drawn from entry to now, the selection and how the window moves.
//

import Foundation
import Observation

/// An open position on the chart: a box from entry to now, with its live profit or loss.
public struct TradeChartOpenPosition: Identifiable, Hashable {
    /// The position as a trade that "exits" now at the mark price, so it gets the same box as a closed trade.
    public let trade: BacktestTrade
    /// Unrealized profit or loss in the account currency.
    public let pnl: Double
    /// Unrealized profit or loss as a share of the position's margin.
    public let pct: Double
    public let currency: String

    public var id: String { trade.id }

    public init(trade: BacktestTrade, pnl: Double, pct: Double, currency: String) {
        self.trade = trade; self.pnl = pnl; self.pct = pct; self.currency = currency
    }
}

public protocol TradeChartModel: AnyObject, Observable {
    var symbol: String { get }
    var timeframe: BacktestTimeframe { get }
    /// Visible window, UTC milliseconds.
    var window: ClosedRange<Double> { get }
    var span: Double { get }
    var selectedTradeID: String? { get set }

    /// Closed trades of the shown symbol inside the window.
    var chartTrades: [BacktestTrade] { get }
    /// Another run's trades, drawn as plain purple boxes (backtest comparison).
    var comparedTrades: [BacktestTrade] { get }
    /// Positions still open, drawn from entry to now.
    var openPositions: [TradeChartOpenPosition] { get }
    /// nil when the chart never follows new bars (a backtest); otherwise whether it is following them right now.
    var followsLatestState: Bool? { get }

    func visibleBars(limit: Int) -> [BacktestBar]
    func candleSpan(_ visible: [BacktestBar]) -> Double
    func priceDomain(_ bars: [BacktestBar]) -> ClosedRange<Double>
    func trade(at t: Double, price: Double, in trades: [BacktestTrade]) -> BacktestTrade?
    /// A box clicked on the chart (nil: a click on empty space).
    func select(_ trade: BacktestTrade?)
    func setWindow(center: Double, width: Double)
    func pan(by milliseconds: Double)
    func zoom(by scale: Double, around anchor: Double?)
    func goToLatest()
}

public extension TradeChartModel {
    var comparedTrades: [BacktestTrade] { [] }
    var openPositions: [TradeChartOpenPosition] { [] }
    var followsLatestState: Bool? { nil }
    func goToLatest() {}
    func select(_ trade: BacktestTrade?) { selectedTradeID = trade?.id }

    /// The narrowest trade box under a point.
    func trade(at t: Double, price: Double, in trades: [BacktestTrade]) -> BacktestTrade? {
        trades.filter { $0.boxContains(t: t, price: price) }
            .min { ($0.exitT - $0.entryT) < ($1.exitT - $1.entryT) }
    }
}

/// Window arithmetic shared by the chart models.
public enum TradeChartMath {
    /// Bars inside the window (plus one either side), merged so the chart never draws more than `limit`.
    public static func visibleBars(_ all: [BacktestBar], window: ClosedRange<Double>, limit: Int) -> [BacktestBar] {
        guard !all.isEmpty else { return [] }
        let low = max(0, BacktestViewerModel.index(in: all, atOrBefore: window.lowerBound) - 1)
        let high = min(all.count - 1, BacktestViewerModel.index(in: all, atOrBefore: window.upperBound) + 1)
        guard low <= high else { return [] }
        let slice = all[low...high]
        guard slice.count > limit else { return Array(slice) }
        let stride = Int((Double(slice.count) / Double(limit)).rounded(.up))
        var merged: [BacktestBar] = []
        merged.reserveCapacity(slice.count / stride + 1)
        var index = slice.startIndex
        while index < slice.endIndex {
            let group = slice[index..<min(index + stride, slice.endIndex)]
            merged.append(BacktestBar(t: group.first!.t, o: group.first!.o, h: group.map(\.h).max()!,
                                      l: group.map(\.l).min()!, c: group.last!.c, v: group.map(\.v).reduce(0, +)))
            index += stride
        }
        return merged
    }

    /// Price axis for the visible bars, widened to the given levels (a selected trade's stops and targets),
    /// with room below for the selected trade's size blocks.
    public static func priceDomain(_ bars: [BacktestBar], including levels: [Double]) -> ClosedRange<Double> {
        var low = bars.map(\.l).min() ?? levels.min() ?? 0
        var high = bars.map(\.h).max() ?? levels.max() ?? 1
        if let min = levels.min() { low = Swift.min(low, min) }
        if let max = levels.max() { high = Swift.max(high, max) }
        let pad = max((high - low) * 0.08, high * 0.002)
        return (low - pad * 1.6)...(high + pad)
    }
}
