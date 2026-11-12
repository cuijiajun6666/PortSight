//
//  LiveViewerModel.swift
//  PortSightKit
//
//  Page state for 交易 · 实时: which account (模拟盘 / 实盘 / 影子账本), which model and contract, the chart's
//  timeframe and window (following the newest bar unless the user has panned away), and the selected trade or
//  position. Read-only: nothing here can place, cancel or change an order.
//

import Foundation
import Observation

@Observable
public final class LiveViewerModel: TradeChartModel {
    public let feed: LiveFeed

    public var accountKind: LiveAccountKind = .paper {
        didSet { if oldValue != accountKind { accountChanged() } }
    }
    /// nil shows every model of the account.
    public var modelFilter: String? {
        didSet { if oldValue != modelFilter { selectedTradeID = nil; keepContractValid() } }
    }
    public var contract: String = "BTCUSDT"
    public private(set) var timeframe: BacktestTimeframe = .m5
    public var selectedTradeID: String?
    /// While true the window keeps the newest bar at its right edge.
    public private(set) var followsLatest = true

    public static let timeframes: [BacktestTimeframe] = [.m1, .m5, .m15, .h1]
    public static let defaultBars = 160.0
    /// Empty candles kept to the right of the newest bar.
    private static let rightMargin = 8.0

    private var manualWindow: ClosedRange<Double> = 0...1
    private var width: Double

    public init(feed: LiveFeed = LiveFeed()) {
        self.feed = feed
        width = Self.defaultBars * BacktestTimeframe.m5.seconds * 1_000
        keepContractValid()
    }

    // MARK: Account and filters

    public var account: LiveAccount? { feed.account(accountKind) }
    public var showsMoney: Bool { accountKind.showsMoney }
    private var accountID: String { account?.id ?? "" }

    /// Models of the chosen account.
    public var accountModels: [LiveModelStatus] { feed.models.filter { $0.accountId == accountID } }
    public var visibleModels: [LiveModelStatus] {
        accountModels.filter { modelFilter == nil || $0.model == modelFilter }
    }

    private func matches(_ accountId: String, _ model: String) -> Bool {
        showsMoney && accountId == accountID && (modelFilter == nil || model == modelFilter)
    }

    public var positions: [LivePosition] { feed.positions.filter { matches($0.accountId, $0.model) } }
    public var openOrders: [LiveOrder] {
        feed.orders.filter { $0.status.isOpen && matches($0.accountId, $0.model) }.reversed()
    }
    /// Fills, newest first.
    public var fills: [LiveFill] { feed.fills.filter { matches($0.accountId, $0.model) }.reversed() }
    public var trades: [LiveTradeRecord] { feed.closedTrades.filter { matches($0.accountId, $0.model) } }

    /// Every contract the account (and model) traded or holds, with its trade count; the feed's contracts when none.
    public var contractCounts: [(contract: String, count: Int)] {
        var counts: [String: Int] = [:]
        for trade in trades { counts[trade.trade.symbol, default: 0] += 1 }
        for position in positions { counts[position.contract, default: 0] += 1 }
        if counts.isEmpty {
            for model in visibleModels { for contract in model.contracts { counts[contract] = 0 } }
        }
        if counts.isEmpty { for contract in LiveFeed.contracts { counts[contract] = 0 } }
        return counts.map { ($0.key, $0.value) }.sorted { $0.contract < $1.contract }
    }

    private func accountChanged() {
        modelFilter = nil
        selectedTradeID = nil
        keepContractValid()
        goToLatest()
    }

    private func keepContractValid() {
        let available = contractCounts.map(\.contract)
        if !available.contains(contract) { contract = available.first ?? LiveFeed.contracts[0] }
    }

    public func changeContract(_ new: String) {
        guard new != contract else { return }
        contract = new
        if let trade = selectedTrade, trade.symbol != new { selectedTradeID = nil }
        goToLatest()
    }

    // MARK: Selection

    public var selectedPosition: LivePosition? {
        selectedTradeID.flatMap { id in positions.first { $0.tradeId == id } }
    }

    public var selectedRecord: LiveTradeRecord? {
        selectedTradeID.flatMap { id in trades.first { $0.trade.id == id } }
    }

    /// The selected closed trade, or the selected open position as a trade running to now.
    public var selectedTrade: BacktestTrade? {
        if let record = selectedRecord { return record.trade }
        if let position = selectedPosition { return position.chartTrade(now: feed.now, equity: account?.equity ?? 1) }
        return nil
    }

    /// A box clicked on the chart: selects it and, when part of the trade is off screen, moves the window just enough
    /// to show all of it (widening it only when the trade is longer than the window).
    public func select(_ trade: BacktestTrade?) {
        guard let trade else {
            selectedTradeID = nil
            return
        }
        selectedTradeID = trade.id
        let current = window
        let length = max(trade.exitT - trade.entryT, candle)
        let pad = max(length * 0.12, 3 * candle)
        if positions.contains(where: { $0.tradeId == trade.id }) {
            // An open position runs to now: keep (or go back to) following the newest bar, widened until its entry
            // is in view, so its live end never slides off the right edge.
            guard trade.entryT - pad < current.lowerBound || !followsLatest else { return }
            useTimeframeCovering(trade.entryT)
            // When following, the left edge is liveEdge - width, and liveEdge = newest bar + max(margin, 0.14 width).
            let newest = bars.last?.t ?? feed.now
            let needed = newest - (trade.entryT - pad)
            let wanted = max(needed + Self.rightMargin * candle, needed / 0.86)
            width = min(max(wanted, width, 30 * candle), maxWidth)
            followsLatest = true
            return
        }
        guard trade.entryT - pad < current.lowerBound || trade.exitT + pad > current.upperBound else { return }
        useTimeframeCovering(trade.entryT)
        let span = self.span
        if length + 2 * pad <= span {
            var low = current.lowerBound
            if trade.entryT - pad < low { low = trade.entryT - pad }
            if trade.exitT + pad > low + span { low = trade.exitT + pad - span }
            setWindow(center: low + span / 2, width: span)
        } else {
            setWindow(center: (trade.entryT + trade.exitT) / 2, width: length + 2 * pad)
        }
    }

    /// Shows a closed trade on the chart and selects it.
    public func focus(_ trade: BacktestTrade) {
        if trade.symbol != contract { contract = trade.symbol }
        selectedTradeID = trade.id
        // 1-minute bars only cover the last two days: an older trade needs a coarser timeframe.
        useTimeframeCovering(trade.entryT)
        let length = max(trade.exitT - trade.entryT, candle)
        let width = max(length * 2.6, 80 * candle)
        setWindow(center: (trade.entryT + trade.exitT) / 2, width: width)
    }

    /// Shows an open position from its entry to now and selects it.
    public func focus(_ position: LivePosition) {
        if position.contract != contract { contract = position.contract }
        selectedTradeID = position.tradeId
        useTimeframeCovering(position.openedAt)
        let length = max(feed.now - position.openedAt, candle)
        width = min(max(length * 1.6, 80 * candle), maxWidth)
        if !followsLatest { goToLatest() }
    }

    /// Switches to the finest timeframe whose bars reach back to `time`, when the current one does not.
    private func useTimeframeCovering(_ time: Double) {
        func covers(_ timeframe: BacktestTimeframe) -> Bool {
            guard let first = feed.bars(contract, timeframe).first else { return false }
            return first.t <= time
        }
        guard !covers(timeframe) else { return }
        guard let better = Self.timeframes.first(where: covers) ?? Self.timeframes.last, better != timeframe else { return }
        timeframe = better
    }

    /// A fill focuses the trade it belongs to (open or closed).
    public func focus(fill: LiveFill) {
        if let position = feed.positions.first(where: { $0.tradeId == fill.tradeId }) {
            focus(position)
        } else if let record = feed.closedTrades.first(where: { $0.trade.id == fill.tradeId }) {
            focus(record.trade)
        }
    }

    // MARK: TradeChartModel

    public var symbol: String { contract }
    private var candle: Double { timeframe.seconds * 1_000 }
    public var bars: [BacktestBar] { feed.bars(contract, timeframe) }

    /// Right edge while following: room after the newest bar for the open positions' profit labels.
    private var liveEdge: Double { (bars.last?.t ?? feed.now) + max(Self.rightMargin * candle, width * 0.14) }
    private var firstBar: Double { bars.first?.t ?? (feed.now - LiveFeed.historyDays * 86_400_000) }
    private var maxWidth: Double { max(liveEdge - firstBar, 30 * candle) }

    public var window: ClosedRange<Double> {
        if followsLatest {
            let edge = liveEdge
            return (edge - width)...edge
        }
        return manualWindow
    }

    public var span: Double { window.upperBound - window.lowerBound }
    public var followsLatestState: Bool? { followsLatest }

    public var chartTrades: [BacktestTrade] {
        guard showsMoney else { return [] }
        let window = window
        let contract = contract
        return trades.map(\.trade)
            .filter { $0.symbol == contract && $0.exitT >= window.lowerBound && $0.entryT <= window.upperBound }
    }

    public var openPositions: [TradeChartOpenPosition] {
        guard showsMoney else { return [] }
        let equity = account?.equity ?? 1
        let currency = account?.currency ?? "USDT"
        return positions.filter { $0.contract == contract }.map { position in
            TradeChartOpenPosition(trade: position.chartTrade(now: feed.now, equity: equity), pnl: position.unrealizedPnl,
                                   pct: position.unrealizedPct, currency: currency)
        }
    }

    public func visibleBars(limit: Int) -> [BacktestBar] {
        TradeChartMath.visibleBars(bars, window: window, limit: limit)
    }

    public func candleSpan(_ visible: [BacktestBar]) -> Double {
        guard visible.count > 1 else { return candle }
        return visible[1].t - visible[0].t
    }

    public func priceDomain(_ bars: [BacktestBar]) -> ClosedRange<Double> {
        var levels: [Double] = []
        if let trade = selectedTrade, trade.symbol == contract {
            levels = [trade.entryPx, trade.exitPx] + trade.stops.map(\.px) + trade.targets.map(\.px)
        }
        // Open positions keep their entry price in view. Their stop and target do not stretch the scale (like an
        // exchange chart): the box simply runs off the top or bottom, so the candles keep their height.
        for position in positions where position.contract == contract && position.openedAt <= window.upperBound {
            levels.append(position.entryPx)
        }
        return TradeChartMath.priceDomain(bars, including: levels)
    }

    public func setWindow(center: Double, width requested: Double) {
        let edge = liveEdge
        let width = min(max(requested, 30 * candle), maxWidth)
        var low = center - width / 2
        low = min(max(low, edge - maxWidth), edge - width)
        self.width = width
        // Back at (or past) the newest bar: follow again.
        if low + width >= edge - candle * 0.5 {
            followsLatest = true
        } else {
            followsLatest = false
            manualWindow = low...(low + width)
        }
    }

    public func pan(by milliseconds: Double) {
        let current = window
        setWindow(center: (current.lowerBound + current.upperBound) / 2 + milliseconds, width: span)
    }

    public func zoom(by scale: Double, around anchor: Double? = nil) {
        let current = window
        let anchor = followsLatest ? current.upperBound : (anchor ?? (current.lowerBound + current.upperBound) / 2)
        let width = span * scale
        let fraction = (anchor - current.lowerBound) / max(span, 1)
        let low = anchor - fraction * width
        setWindow(center: low + width / 2, width: width)
    }

    public func goToLatest() {
        width = min(max(width, 30 * candle), maxWidth)
        followsLatest = true
    }

    public func showAll() {
        width = maxWidth
        followsLatest = true
    }

    public func changeTimeframe(_ new: BacktestTimeframe) {
        guard new != timeframe else { return }
        let center = (window.lowerBound + window.upperBound) / 2
        let shown = span / candle
        let following = followsLatest
        timeframe = new
        width = min(shown, Self.defaultBars) * candle
        if following { goToLatest() } else { setWindow(center: center, width: width) }
    }
}
