//
//  LiveFeed.swift
//  PortSightKit
//
//  A built-in stand-in for the quant system's live feed (Docs/live_feed_format.md), so the 实时 page can be
//  built before the relay carries the real one. It starts from "now" with 14 days of history: a seeded random
//  walk for BTCUSDT and ETHUSDT (5-minute, 15-minute and 1-hour bars for 14 days, 1-minute bars for the last two),
//  a 模拟盘 account running two models and a small 实盘 account running one, with their closed trades, fills,
//  working stop / take-profit orders and open positions. Every 2 seconds it moves the price, revalues the
//  positions and, every 45–90 seconds, lets a model act (open, add, reduce, move its stop, close).
//
//  Building the 14 days takes most of a second in a debug build, so the apps share one feed built off the main
//  thread (`LiveFeed.shared()`, started early by `prepare()`); after that it is used only on the main actor (its
//  clock runs there).
//
//  The 影子账本 entry only ever has status, signal counts and checks: it never gets positions, fills or money.
//  Nothing here is a real strategy result, and nothing is ever sent anywhere.
//

import Foundation
import Observation

/// Nonisolated so its history can be built off the main thread (`shared()`); once handed over it is used only on
/// the main actor, hence `@unchecked Sendable`.
@Observable
nonisolated public final class LiveFeed: @unchecked Sendable {
    public static let contracts = ["BTCUSDT", "ETHUSDT"]
    /// Seconds between price updates while running.
    public static let tickInterval = 2.0
    public static let historyDays = 14.0
    /// Timeframes the feed keeps bars for (1-minute only for the last two days).
    public static let timeframes: [BacktestTimeframe] = [.m1, .m5, .m15, .h1]
    /// When the shadow ledger's sealed results open.
    public static let shadowUnsealDate = "2027-05-06"

    public private(set) var now: Double
    public private(set) var accounts: [LiveAccount] = []
    public private(set) var positions: [LivePosition] = []
    /// Working orders and the most recent finished ones, oldest first.
    public private(set) var orders: [LiveOrder] = []
    /// Fills, oldest first.
    public private(set) var fills: [LiveFill] = []
    /// Closed trades, oldest first.
    public private(set) var closedTrades: [LiveTradeRecord] = []
    public private(set) var models: [LiveModelStatus] = []
    /// Latest price per contract.
    public private(set) var marks: [String: Double] = [:]
    /// The newest thing a model did (a fill or an order change), for a banner. nil until the first live action.
    public private(set) var lastEvent: LiveEvent?
    /// The event stream since the feed went live, newest last (capped).
    public private(set) var recentEvents: [LiveEvent] = []
    public private(set) var isRunning = false
    /// Grows whenever bars change, so views reading `bars` update.
    public private(set) var barsVersion = 0

    // MARK: Private state

    private final class BarSeries { var bars: [BacktestBar] = [] }

    private struct Plan {
        let accountId: String
        let model: String
        let prefix: String
        let contracts: [String]
        /// Notional of a fresh position as a share of equity.
        let share: Double
        let leverage: Double
        /// Hours between actions while replaying history.
        let gap: ClosedRange<Double>
        /// How long before now the model started trading.
        let since: Double
        /// Positions opened shortly before now, so the page starts with something open.
        let forced: [Forced]
    }

    private struct Forced {
        let contract: String
        let side: BacktestSide
        let minutesBefore: Double
        let addMinutesBefore: Double?
    }

    private struct Book {
        let plan: Int
        let equityAtOpen: Double
        var adds = 0
        var reduced = false
        var best = 0.0
        var worst = 0.0
        var signals: [String: Double]
        var stopOrderID: String?
        var targetOrderID: String?
    }

    @ObservationIgnored private var series: [String: [BacktestTimeframe: BarSeries]] = [:]
    @ObservationIgnored private var rng: SplitMix
    @ObservationIgnored private var timer: Timer?
    /// Pages showing the feed right now (start(for:) / stop(for:)): the clock runs while any is on screen.
    @ObservationIgnored private var clients: Set<AnyHashable> = []
    @ObservationIgnored private var plans: [Plan] = []
    @ObservationIgnored private var books: [String: Book] = [:]
    @ObservationIgnored private var nextAction: [Double] = []
    @ObservationIgnored private var forcedDone: Set<String> = []
    @ObservationIgnored private var nextLiveAction = 0.0
    @ObservationIgnored private var live = false
    @ObservationIgnored private var seq = 0
    @ObservationIgnored private var serial = 0
    @ObservationIgnored private var tradeNumbers: [String: Int] = [:]
    @ObservationIgnored private var day: [String: Int] = [:]
    @ObservationIgnored private var dayStartEquity: [String: Double] = [:]
    @ObservationIgnored private var dayFee: [String: Double] = [:]
    @ObservationIgnored private var lastShadowHour = 0
    @ObservationIgnored private let startedAt: Double

    private static let minute = 60_000.0
    private static let hour = 3_600_000.0
    private static let dayMs = 86_400_000.0
    private static let takerFee = 0.0005
    private static let makerFee = 0.0002

    private static func sigma(_ contract: String) -> Double { contract.hasPrefix("BTC") ? 0.00062 : 0.00082 }
    private static func tick(_ contract: String) -> Double { contract.hasPrefix("BTC") ? 0.1 : 0.01 }
    private static func lot(_ contract: String) -> Double { contract.hasPrefix("BTC") ? 0.001 : 0.01 }
    private static func stopFraction(_ contract: String) -> Double { contract.hasPrefix("BTC") ? 0.014 : 0.018 }
    private static func round(_ value: Double, to step: Double) -> Double { (value / step).rounded() * step }

    // MARK: Init

    /// - Parameters:
    ///   - seed: the same seed and start time always give the same history and the same first ticks.
    ///   - now: where the history ends and the live part starts.
    public init(seed: UInt64 = 20_261_106, now: Date = Date()) {
        rng = SplitMix(seed)
        let end = now.milliseconds
        self.now = end
        startedAt = end
        setUp(end: end)
        replayHistory(until: end)
    }

    @MainActor private static var building: Task<LiveFeed, Never>?

    /// The shared feed once it has been built (nil until then), so a page can show it in its first frame.
    @MainActor public private(set) static var ready: LiveFeed?

    /// The app's feed, built once on a background thread so the 实时 page that asks for it does not stall.
    @MainActor public static func shared() async -> LiveFeed {
        let feed = await sharedTask(priority: .userInitiated).value
        ready = feed
        return feed
    }

    /// Starts building the shared feed in the background (after launch), so the 实时 page usually finds it ready.
    @MainActor public static func prepare() { _ = sharedTask(priority: .utility) }

    @MainActor private static func sharedTask(priority: TaskPriority) -> Task<LiveFeed, Never> {
        if let building { return building }
        let task = Task.detached(priority: priority) { LiveFeed() }
        building = task
        Task { ready = await task.value }
        return task
    }

    // MARK: Running

    /// A page showing the feed came on screen. The feed is shared (one per app), so the 2-second clock runs while
    /// at least one page is on screen; it first catches up with the time it was stopped.
    @MainActor public func start(for client: AnyHashable) {
        clients.insert(client)
        start()
    }

    /// A page showing the feed went off screen; the clock stops when no page is left. An unknown client is ignored.
    @MainActor public func stop(for client: AnyHashable) {
        guard clients.remove(client) != nil, clients.isEmpty else { return }
        stop()
    }

    /// Starts the 2-second clock (and first catches up with the time it was stopped).
    @MainActor func start() {
        guard timer == nil else { return }
        tick(at: Date())
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                // Released without stop(): the timer ends itself instead of firing forever.
                guard let self else { return timer.invalidate() }
                self.tick(at: Date())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
    }

    deinit {
        // Released on the main actor in practice; a timer left behind ends itself on its next fire anyway.
        if Thread.isMainThread { timer?.invalidate() }
    }

    /// Pauses the clock.
    @MainActor func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    /// Moves the feed forward to `date` in 2-second steps (coarser after a long pause).
    public func tick(at date: Date) {
        let target = date.milliseconds
        let gap = target - now
        guard gap > 0 else { return }
        let step = gap <= 10 * Self.minute ? Self.tickInterval * 1_000 : gap / 300
        while now < target {
            advance(to: min(now + step, target))
        }
        // Once per tick, not per step: nothing in the simulation reads these, so a long catch-up (when 实时 first
        // comes on screen) only pays for the last state. Accounts first: the models read their equity and margin.
        refreshAccounts()
        refreshModels()
        barsVersion &+= 1
    }

    // MARK: Reading

    /// Bars for one contract and timeframe, oldest first. 1-minute bars cover the last two days.
    public func bars(_ contract: String, _ timeframe: BacktestTimeframe) -> [BacktestBar] {
        _ = barsVersion
        return series[contract]?[timeframe]?.bars ?? []
    }

    public func account(_ kind: LiveAccountKind) -> LiveAccount? { accounts.first { $0.kind == kind } }
    public func account(id: String) -> LiveAccount? { accounts.first { $0.id == id } }

    /// Everything as the quant system would send it, with the shadow-ledger seal applied.
    public func snapshot() -> LiveSnapshot {
        LiveSnapshot(t: now, accounts: accounts, positions: positions, orders: orders.filter(\.status.isOpen),
                     models: models, fills: fills, closedTrades: closedTrades).sealed()
    }

    // MARK: Set-up

    private func setUp(end: Double) {
        let days = Self.dayMs
        accounts = [
            LiveAccount(id: "paper-1", kind: .paper, name: "模拟盘 · 主账户", balance: 100_000, equity: 100_000,
                        available: 100_000, marginUsed: 0, todayPnl: 0, unrealizedPnl: 0, todayFee: 0, updatedAt: end),
            LiveAccount(id: "live-1", kind: .live, name: "实盘 · 小资金", balance: 8_000, equity: 8_000,
                        available: 8_000, marginUsed: 0, todayPnl: 0, unrealizedPnl: 0, todayFee: 0, updatedAt: end),
            LiveAccount(id: "shadow-1", kind: .shadow, name: "影子账本", balance: nil, equity: nil, available: nil,
                        marginUsed: nil, todayPnl: nil, unrealizedPnl: nil, updatedAt: end),
        ]
        plans = [
            Plan(accountId: "paper-1", model: "v4 G263", prefix: "G263", contracts: ["BTCUSDT", "ETHUSDT"],
                 share: 0.5, leverage: 5, gap: 2...7, since: 14 * days,
                 forced: [Forced(contract: "BTCUSDT", side: .long, minutesBefore: 190, addMinutesBefore: 85)]),
            Plan(accountId: "paper-1", model: "v4 G210", prefix: "G210", contracts: ["ETHUSDT"],
                 share: 0.35, leverage: 3, gap: 3...9, since: 14 * days,
                 forced: [Forced(contract: "ETHUSDT", side: .short, minutesBefore: 55, addMinutesBefore: nil)]),
            Plan(accountId: "live-1", model: "v4 G263", prefix: "L263", contracts: ["BTCUSDT"],
                 share: 0.4, leverage: 3, gap: 6...16, since: 6 * days,
                 forced: [Forced(contract: "BTCUSDT", side: .long, minutesBefore: 190, addMinutesBefore: nil)]),
        ]
        nextAction = plans.map { end - $0.since + rng.uniform() * 3 * Self.hour }
        models = plans.map { plan in
            LiveModelStatus(accountId: plan.accountId, model: plan.model, state: .running, lastRun: nil, nextRun: nil,
                            signals: [:], checks: [], signalsToday: 0, signalsTotal: 0, contracts: plan.contracts)
        } + [
            LiveModelStatus(accountId: "shadow-1", model: "v3.0 主线", state: .running, lastRun: nil, nextRun: nil,
                            signals: [:], checks: [], signalsToday: 0, signalsTotal: 118, contracts: Self.contracts),
            LiveModelStatus(accountId: "shadow-1", model: "挑战者 C1", state: .running, lastRun: nil, nextRun: nil,
                            signals: [:], checks: [], signalsToday: 0, signalsTotal: 96, contracts: Self.contracts),
            LiveModelStatus(accountId: "shadow-1", model: "挑战者 C2", state: .error, lastRun: nil, nextRun: nil,
                            signals: [:], checks: [], signalsToday: 0, signalsTotal: 41, contracts: ["ETHUSDT"],
                            message: "行情延迟 7 分钟，暂停出信号"),
        ]
        for contract in Self.contracts {
            series[contract] = Dictionary(uniqueKeysWithValues: Self.timeframes.map { ($0, BarSeries()) })
        }
    }

    /// Seeded 1-minute walk for both contracts (ETH partly follows BTC), scaled to end near today's prices.
    private func generateMinutes(from start: Double, to end: Double) -> [String: [BacktestBar]] {
        let count = Int(((end - start) / Self.minute).rounded(.up))
        var walks: [String: [BacktestBar]] = [:]
        var prices = ["BTCUSDT": 1.0, "ETHUSDT": 1.0]
        var out: [String: [BacktestBar]] = ["BTCUSDT": [], "ETHUSDT": []]
        out["BTCUSDT"]?.reserveCapacity(count)
        out["ETHUSDT"]?.reserveCapacity(count)
        for i in 0..<count {
            let t = start + Double(i) * Self.minute
            let common = rng.normal(), own = rng.normal()
            let swing = 1 + 0.5 * sin(t / (2.7 * Self.dayMs))
            for contract in Self.contracts {
                let z = contract.hasPrefix("BTC") ? common : 0.75 * common + 0.66 * own
                let sigma = Self.sigma(contract) * swing
                let drift = 0.000004 * sin(t / (4.1 * Self.dayMs) + (contract.hasPrefix("BTC") ? 0 : 1.3))
                let open = prices[contract]!
                let close = open * exp(drift + z * sigma)
                let wick = rng.uniform() < 0.003 ? 3.5 : 1.0
                let high = max(open, close) * (1 + abs(rng.normal()) * sigma * 0.4 * wick)
                let low = min(open, close) * (1 - abs(rng.normal()) * sigma * 0.4 * wick)
                out[contract]!.append(BacktestBar(t: t, o: open, h: high, l: low, c: close, v: 1 + rng.uniform() * 4))
                prices[contract] = close
            }
        }
        let targets = ["BTCUSDT": 68_420.0, "ETHUSDT": 2_468.0]
        for contract in Self.contracts {
            let scale = targets[contract]! / (out[contract]!.last?.c ?? 1)
            let tick = Self.tick(contract)
            let volumeScale = contract.hasPrefix("BTC") ? 9.0 : 140.0
            walks[contract] = out[contract]!.map { bar in
                BacktestBar(t: bar.t, o: Self.round(bar.o * scale, to: tick), h: Self.round(bar.h * scale, to: tick),
                            l: Self.round(bar.l * scale, to: tick), c: Self.round(bar.c * scale, to: tick),
                            v: bar.v * volumeScale)
            }
        }
        return walks
    }

    private func replayHistory(until end: Double) {
        let start = ((end - Self.historyDays * Self.dayMs) / Self.minute).rounded(.down) * Self.minute
        let minutes = generateMinutes(from: start, to: end)
        let count = minutes["BTCUSDT"]?.count ?? 0
        for contract in Self.contracts { day[contract] = 0 }
        lastShadowHour = Int(start / Self.hour)
        for i in 0..<count {
            var ranges: [String: (low: Double, high: Double, close: Double)] = [:]
            var t = start
            for contract in Self.contracts {
                let bar = minutes[contract]![i]
                ingest(contract, t: bar.t, open: bar.o, high: bar.h, low: bar.l, close: bar.c, volume: bar.v)
                ranges[contract] = (bar.l, bar.h, bar.c)
                marks[contract] = bar.c
                t = bar.t
            }
            now = min(t + Self.minute, end)
            process(ranges)
        }
        now = end
        // Keep 1-minute bars for the last two days only.
        for contract in Self.contracts {
            if let m1 = series[contract]?[.m1] {
                let cutoff = end - 2 * Self.dayMs
                m1.bars.removeAll { $0.t < cutoff }
            }
        }
        live = true
        nextLiveAction = end + 12_000 + rng.uniform() * 10_000
        refreshAccounts()
        refreshModels()
    }

    // MARK: Simulation

    /// One live step: move both prices, then let the models react.
    private func advance(to t: Double) {
        let seconds = (t - now) / 1_000
        now = t
        let common = rng.normal(), own = rng.normal()
        var ranges: [String: (low: Double, high: Double, close: Double)] = [:]
        for contract in Self.contracts {
            let previous = marks[contract] ?? 1
            let z = contract.hasPrefix("BTC") ? common : 0.75 * common + 0.66 * own
            let moved = Self.round(previous * exp(z * Self.sigma(contract) * (seconds / 60).squareRoot()),
                                   to: Self.tick(contract))
            let volume = (contract.hasPrefix("BTC") ? 0.3 : 4.5) * seconds * (0.5 + rng.uniform())
            ingest(contract, t: t, open: previous, high: max(previous, moved), low: min(previous, moved),
                   close: moved, volume: volume)
            marks[contract] = moved
            ranges[contract] = (min(previous, moved), max(previous, moved), moved)
        }
        if let m1 = series["BTCUSDT"]?[.m1], m1.bars.count > 2 * 1_440 + 120 {
            for contract in Self.contracts { series[contract]?[.m1]?.bars.removeFirst(60) }
        }
        process(ranges)
    }

    private func ingest(_ contract: String, t: Double, open: Double, high: Double, low: Double, close: Double, volume: Double) {
        guard let set = series[contract] else { return }
        for (timeframe, store) in set {
            let span = timeframe.seconds * 1_000
            let bucket = (t / span).rounded(.down) * span
            if let last = store.bars.last, last.t == bucket {
                store.bars[store.bars.count - 1] = BacktestBar(t: bucket, o: last.o, h: max(last.h, high),
                                                               l: min(last.l, low), c: close, v: last.v + volume)
            } else if store.bars.last.map({ $0.t < bucket }) ?? true {
                store.bars.append(BacktestBar(t: bucket, o: open, h: high, l: low, c: close, v: volume))
            }
        }
    }

    /// Triggers, day boundaries and model actions after prices moved over `ranges`.
    private func process(_ ranges: [String: (low: Double, high: Double, close: Double)]) {
        let t = now
        // Stops and targets first, then revalue what is still open.
        for index in positions.indices.reversed() {
            let position = positions[index]
            guard let range = ranges[position.contract] else { continue }
            let long = position.side == .long
            if let stop = position.stopPx, long ? range.low <= stop : range.high >= stop {
                close(index, price: stop, reason: "stop_loss", trigger: books[position.id]?.stopOrderID)
                continue
            }
            if let target = position.targetPx, long ? range.high >= target : range.low <= target {
                close(index, price: target, reason: "take_profit", trigger: books[position.id]?.targetOrderID)
                continue
            }
            positions[index].revalue(mark: range.close)
            if var book = books[position.id] {
                let share = positions[index].unrealizedPnl / max(book.equityAtOpen, 1)
                book.best = max(book.best, share)
                book.worst = min(book.worst, share)
                books[position.id] = book
            }
        }
        fillWaitingEntries(ranges)

        // UTC day boundary: today's profit and fees start again.
        let today = Int(t / Self.dayMs)
        for account in accounts where account.kind.showsMoney && day[account.id] != today {
            day[account.id] = today
            dayStartEquity[account.id] = equity(of: account.id)
            dayFee[account.id] = 0
        }
        shadowSignals(at: t)

        if live {
            if t >= nextLiveAction {
                nextLiveAction = t + 45_000 + rng.uniform() * 45_000
                liveAction(at: t)
            }
        } else {
            for (index, plan) in plans.enumerated() {
                if t >= startedAt - plan.since, t >= nextAction[index] {
                    nextAction[index] = t + (plan.gap.lowerBound + rng.uniform() * (plan.gap.upperBound - plan.gap.lowerBound)) * Self.hour
                    // The last hours belong to the positions opened just before now.
                    if plan.forced.isEmpty || t < startedAt - 4 * Self.hour { historyAction(index, at: t) }
                }
                forcedActions(index, at: t)
            }
        }
    }

    private func historyAction(_ planIndex: Int, at t: Double) {
        let plan = plans[planIndex]
        let contract = plan.contracts[Int(rng.uniform() * Double(plan.contracts.count)) % plan.contracts.count]
        act(planIndex, contract: contract, at: t, allowLimit: false)
    }

    private func liveAction(at t: Double) {
        // Paper models act most; the live account now and then.
        let roll = rng.uniform()
        let planIndex = roll < 0.45 ? 0 : roll < 0.8 ? 1 : 2
        let plan = plans[planIndex]
        let contract = plan.contracts[Int(rng.uniform() * Double(plan.contracts.count)) % plan.contracts.count]
        act(planIndex, contract: contract, at: t, allowLimit: true)
    }

    /// Positions opened (and added to) shortly before now, so the page starts with open positions.
    private func forcedActions(_ planIndex: Int, at t: Double) {
        let plan = plans[planIndex]
        for forced in plan.forced {
            let key = "\(planIndex)-\(forced.contract)"
            let openAt = startedAt - forced.minutesBefore * Self.minute
            if t >= openAt, !forcedDone.contains(key) {
                forcedDone.insert(key)
                if let index = positionIndex(plan, forced.contract) { close(index, price: marks[forced.contract]!, reason: "signal_reverse", trigger: nil) }
                open(planIndex, contract: forced.contract, side: forced.side, price: marks[forced.contract]!, at: t,
                     stopFraction: Self.stopFraction(forced.contract) * 2.2)
            }
            if let addBefore = forced.addMinutesBefore, t >= startedAt - addBefore * Self.minute,
               !forcedDone.contains(key + "-add"), let index = positionIndex(plan, forced.contract) {
                forcedDone.insert(key + "-add")
                change(index, fraction: 0.5, price: marks[forced.contract]!, at: t, reason: "add")
            }
        }
    }

    private func positionIndex(_ plan: Plan, _ contract: String) -> Int? {
        positions.firstIndex { $0.accountId == plan.accountId && $0.model == plan.model && $0.contract == contract }
    }

    /// What a model does when it runs: open when flat; otherwise add, reduce, move the stop or close.
    private func act(_ planIndex: Int, contract: String, at t: Double, allowLimit: Bool) {
        let plan = plans[planIndex]
        guard let price = marks[contract] else { return }
        let mu = momentum(contract, bars: 48)
        guard let index = positionIndex(plan, contract) else {
            // Don't stack a second entry while a limit entry is still waiting.
            if orders.contains(where: { $0.accountId == plan.accountId && $0.model == plan.model && $0.contract == contract
                && !$0.reduceOnly && $0.status.isOpen }) { return }
            let side: BacktestSide = (mu >= 0) != (rng.uniform() < 0.2) ? .long : .short
            if allowLimit && rng.uniform() < 0.4 {
                placeLimitEntry(planIndex, contract: contract, side: side, price: price, at: t)
            } else {
                open(planIndex, contract: contract, side: side, price: price, at: t)
            }
            return
        }
        let position = positions[index]
        let book = books[position.id]
        let roll = rng.uniform()
        let held = (t - position.openedAt) / Self.hour
        if roll < 0.28, (book?.adds ?? 0) < 2, position.unrealizedPnl > 0 || !live {
            change(index, fraction: 0.5, price: price, at: t, reason: "add")
        } else if roll < 0.48, !(book?.reduced ?? false) {
            change(index, fraction: -0.4, price: price, at: t, reason: position.unrealizedPnl > 0 ? "partial_tp" : "reduce")
        } else if roll < 0.7 {
            trailStop(index, price: price, at: t)
        } else {
            let against = position.side.sign * mu < 0
            close(index, price: price, reason: against ? "signal_reverse" : held > 30 ? "time_exit" : "signal_exit", trigger: nil)
        }
    }

    // MARK: Orders and positions

    private func nextID(_ prefix: String) -> String {
        serial += 1
        return prefix + String(format: "%06d", serial)
    }

    private func newTradeID(_ plan: Plan, _ contract: String) -> String {
        let key = plan.prefix + contract
        let number = (tradeNumbers[key] ?? 0) + 1
        tradeNumbers[key] = number
        return plan.prefix + "-" + contract.prefix(3) + String(format: "%04d", number)
    }

    private func lotSize(_ plan: Plan, _ contract: String, price: Double) -> Double {
        let equity = equity(of: plan.accountId)
        return max(Self.lot(contract), Self.round(equity * plan.share / price, to: Self.lot(contract)))
    }

    private func placeLimitEntry(_ planIndex: Int, contract: String, side: BacktestSide, price: Double, at t: Double) {
        let plan = plans[planIndex]
        let limit = Self.round(price * (1 - side.sign * 0.0006), to: Self.tick(contract))
        let order = LiveOrder(id: nextID("O"), accountId: plan.accountId, model: plan.model, contract: contract,
                              type: .limit, side: side == .long ? .buy : .sell, positionSide: side, reduceOnly: false,
                              price: limit, size: lotSize(plan, contract, price: price), createdAt: t)
        record(order)
        emit(.order, plan.accountId, order: order, headline: true)
    }

    /// Limit entries fill when the price reaches them; after four minutes they are cancelled.
    private func fillWaitingEntries(_ ranges: [String: (low: Double, high: Double, close: Double)]) {
        for order in orders where order.status.isOpen && !order.reduceOnly && order.type == .limit {
            guard let range = ranges[order.contract], let price = order.price,
                  let planIndex = plans.firstIndex(where: { $0.accountId == order.accountId && $0.model == order.model }) else { continue }
            let reached = order.side == .buy ? range.low <= price : range.high >= price
            if reached {
                open(planIndex, contract: order.contract, side: order.positionSide, price: price, at: now, entryOrder: order)
            } else if now - order.createdAt > 4 * Self.minute {
                var canceled = order
                canceled.status = .canceled
                canceled.updatedAt = now
                record(canceled)
                emit(.order, order.accountId, order: canceled, headline: true)
            }
        }
    }

    private func open(_ planIndex: Int, contract: String, side: BacktestSide, price: Double, at t: Double,
                      entryOrder: LiveOrder? = nil, stopFraction: Double? = nil) {
        let plan = plans[planIndex]
        let equity = equity(of: plan.accountId)
        let size = entryOrder?.size ?? lotSize(plan, contract, price: price)
        let tradeID = newTradeID(plan, contract)
        let maker = entryOrder != nil
        let fee = price * size * (maker ? Self.makerFee : Self.takerFee)

        var order = entryOrder ?? LiveOrder(id: nextID("O"), accountId: plan.accountId, model: plan.model,
                                            contract: contract, type: .market, side: side == .long ? .buy : .sell,
                                            positionSide: side, reduceOnly: false, price: nil, size: size, createdAt: t)
        order.filled = size
        order.status = .filled
        order.updatedAt = t
        order.tradeId = tradeID
        record(order)

        let stopDistance = stopFraction ?? Self.stopFraction(contract) * (0.8 + rng.uniform() * 0.5)
        let stop = Self.round(price * (1 - side.sign * stopDistance), to: Self.tick(contract))
        let target: Double? = rng.uniform() < 0.65
            ? Self.round(price * (1 + side.sign * stopDistance * (1.8 + rng.uniform())), to: Self.tick(contract)) : nil
        let weight = side.sign * size * price / max(equity, 1)
        var position = LivePosition(id: "P-" + tradeID, accountId: plan.accountId, model: plan.model, contract: contract,
                                    side: side, size: size, leverage: plan.leverage, entryPx: price, markPx: price,
                                    stopPx: stop, targetPx: target, openedAt: t, tradeId: tradeID,
                                    sizePath: [BacktestSizeStep(t: t, w: weight, why: "open")],
                                    stops: [BacktestLevel(t: t, px: stop)],
                                    targets: target.map { [BacktestLevel(t: t, px: $0)] } ?? [], fee: fee)
        position.revalue(mark: marks[contract] ?? price)

        var book = Book(plan: planIndex, equityAtOpen: equity,
                        signals: ["mu_4h": momentum(contract, bars: 48), "mu_1d": momentum(contract, bars: 288)])
        let closeSide: LiveOrderSide = side == .long ? .sell : .buy
        let stopOrder = LiveOrder(id: nextID("O"), accountId: plan.accountId, model: plan.model, contract: contract,
                                  type: .stop, side: closeSide, positionSide: side, reduceOnly: true, price: stop,
                                  size: size, createdAt: t, tradeId: tradeID)
        record(stopOrder)
        book.stopOrderID = stopOrder.id
        if let target {
            let targetOrder = LiveOrder(id: nextID("O"), accountId: plan.accountId, model: plan.model, contract: contract,
                                        type: .takeProfit, side: closeSide, positionSide: side, reduceOnly: true,
                                        price: target, size: size, createdAt: t, tradeId: tradeID)
            record(targetOrder)
            book.targetOrderID = targetOrder.id
        }
        books[position.id] = book
        positions.append(position)
        charge(plan.accountId, realized: 0, fee: fee)

        let fill = LiveFill(id: nextID("F"), accountId: plan.accountId, model: plan.model, orderId: order.id,
                            tradeId: tradeID, t: t, contract: contract, side: side == .long ? .buy : .sell,
                            positionSide: side, action: .open, price: price, size: size, fee: fee, realizedPnl: 0,
                            reason: "signal")
        fills.append(fill)
        emit(.position, plan.accountId, position: position, headline: false)
        emit(.fill, plan.accountId, fill: fill, headline: true)
    }

    /// Adds (fraction > 0) or reduces (fraction < 0) a position by a share of its size.
    private func change(_ index: Int, fraction: Double, price: Double, at t: Double, reason: String) {
        var position = positions[index]
        guard var book = books[position.id] else { return }
        let plan = plans[book.plan]
        let quantity = max(Self.lot(position.contract), Self.round(position.size * abs(fraction), to: Self.lot(position.contract)))
        let adding = fraction > 0
        guard adding || quantity < position.size else { return }
        let fee = price * quantity * Self.takerFee
        let realized = adding ? 0 : position.side.sign * (price - position.entryPx) * quantity
        let orderSide: LiveOrderSide = (position.side == .long) == adding ? .buy : .sell
        var order = LiveOrder(id: nextID("O"), accountId: position.accountId, model: position.model,
                              contract: position.contract, type: .market, side: orderSide, positionSide: position.side,
                              reduceOnly: !adding, price: nil, size: quantity, createdAt: t, tradeId: position.tradeId)
        order.filled = quantity
        order.status = .filled
        record(order)

        if adding {
            position.entryPx = (position.entryPx * position.size + price * quantity) / (position.size + quantity)
            position.size += quantity
            book.adds += 1
        } else {
            position.size -= quantity
            book.reduced = true
        }
        position.realizedPnl += realized
        position.fee += fee
        let equity = equity(of: plan.accountId)
        position.sizePath.append(BacktestSizeStep(t: t, w: position.side.sign * position.size * price / max(equity, 1), why: reason))
        position.revalue(mark: marks[position.contract] ?? price)
        positions[index] = position
        books[position.id] = book
        resizeExits(position, book, at: t)
        charge(position.accountId, realized: realized, fee: fee)

        let fill = LiveFill(id: nextID("F"), accountId: position.accountId, model: position.model, orderId: order.id,
                            tradeId: position.tradeId, t: t, contract: position.contract, side: orderSide,
                            positionSide: position.side, action: adding ? .add : .reduce, price: price,
                            size: quantity, fee: fee, realizedPnl: realized, reason: reason)
        fills.append(fill)
        emit(.position, position.accountId, position: position, headline: false)
        emit(.fill, position.accountId, fill: fill, headline: true)
    }

    /// Stop and take-profit orders follow the position's size.
    private func resizeExits(_ position: LivePosition, _ book: Book, at t: Double) {
        for id in [book.stopOrderID, book.targetOrderID].compactMap({ $0 }) {
            guard var order = orders.first(where: { $0.id == id }), order.status.isOpen else { continue }
            order.size = position.size
            order.updatedAt = t
            record(order)
        }
    }

    /// Tightens the stop when the price has moved in the position's favour.
    private func trailStop(_ index: Int, price: Double, at t: Double) {
        var position = positions[index]
        guard let current = position.stopPx, let book = books[position.id] else { return }
        let trailed = Self.round(price * (1 - position.side.sign * Self.stopFraction(position.contract) * 0.75),
                                 to: Self.tick(position.contract))
        guard position.side.sign * (trailed - current) > 0 else { return }
        position.stopPx = trailed
        position.stops.append(BacktestLevel(t: t, px: trailed))
        positions[index] = position
        if let id = book.stopOrderID, var order = orders.first(where: { $0.id == id }) {
            order.price = trailed
            order.updatedAt = t
            record(order)
            emit(.order, position.accountId, order: order, headline: true)
        }
    }

    private func close(_ index: Int, price: Double, reason: String, trigger: String?) {
        let position = positions[index]
        let book = books[position.id]
        let t = now
        let fee = price * position.size * (reason == "take_profit" ? Self.makerFee : Self.takerFee)
        let realized = position.side.sign * (price - position.entryPx) * position.size
        let closeSide: LiveOrderSide = position.side == .long ? .sell : .buy

        // The triggered exit order fills; the other one is cancelled; a signal exit is a market order.
        var orderID = trigger ?? ""
        for id in [book?.stopOrderID, book?.targetOrderID].compactMap({ $0 }) {
            guard var order = orders.first(where: { $0.id == id }), order.status.isOpen else { continue }
            if id == trigger {
                order.filled = order.size
                order.status = .filled
            } else {
                order.status = .canceled
            }
            order.updatedAt = t
            record(order)
        }
        if trigger == nil {
            var order = LiveOrder(id: nextID("O"), accountId: position.accountId, model: position.model,
                                  contract: position.contract, type: .market, side: closeSide, positionSide: position.side,
                                  reduceOnly: true, price: nil, size: position.size, createdAt: t, tradeId: position.tradeId)
            order.filled = position.size
            order.status = .filled
            record(order)
            orderID = order.id
        }
        charge(position.accountId, realized: realized, fee: fee)

        let fill = LiveFill(id: nextID("F"), accountId: position.accountId, model: position.model, orderId: orderID,
                            tradeId: position.tradeId, t: t, contract: position.contract, side: closeSide,
                            positionSide: position.side, action: .close, price: price, size: position.size, fee: fee,
                            realizedPnl: realized, reason: reason)
        fills.append(fill)

        let totalRealized = position.realizedPnl + realized
        let totalFee = position.fee + fee
        let nav = max(book?.equityAtOpen ?? 1, 1)
        let trade = BacktestTrade(
            id: position.tradeId, symbol: position.contract, side: position.side, entryT: position.openedAt,
            entryPx: position.entryPx, exitT: max(t, position.openedAt + Self.minute), exitPx: price, exitReason: reason,
            sizePath: position.sizePath, stops: position.stops, targets: position.targets,
            pnlGross: totalRealized / nav, fee: totalFee / nav, funding: 0, pnlNet: (totalRealized - totalFee) / nav,
            mfe: book?.best ?? 0, mae: book?.worst ?? 0, holdH: (t - position.openedAt) / Self.hour,
            signalsAtEntry: book?.signals ?? [:])
        closedTrades.append(LiveTradeRecord(accountId: position.accountId, model: position.model, trade: trade,
                                            realizedPnl: totalRealized, fee: totalFee))
        positions.remove(at: index)
        books[position.id] = nil
        emit(.positionClosed, position.accountId, positionID: position.id, headline: false)
        emit(.fill, position.accountId, fill: fill, headline: true)
    }

    private func record(_ order: LiveOrder) {
        if let index = orders.firstIndex(where: { $0.id == order.id }) {
            orders[index] = order
        } else {
            orders.append(order)
        }
        // Keep every working order and the last 300 finished ones.
        let finished = orders.filter { !$0.status.isOpen }.count
        if finished > 340 {
            var drop = finished - 300
            orders.removeAll { order in
                guard drop > 0, !order.status.isOpen else { return false }
                drop -= 1
                return true
            }
        }
    }

    private func charge(_ accountID: String, realized: Double, fee: Double) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[index].balance = (accounts[index].balance ?? 0) + realized - fee
        dayFee[accountID, default: 0] += fee
    }

    private func emit(_ type: LiveEventType, _ accountID: String, fill: LiveFill? = nil, order: LiveOrder? = nil,
                      position: LivePosition? = nil, positionID: String? = nil, headline: Bool) {
        guard live else { return }
        seq += 1
        let event = LiveEvent(seq: seq, t: now, type: type, accountId: accountID, fill: fill, order: order,
                              position: position, positionId: positionID)
        recentEvents.append(event)
        if recentEvents.count > 200 { recentEvents.removeFirst(recentEvents.count - 200) }
        if headline { lastEvent = event }
    }

    // MARK: Accounts and models

    private func equity(of accountID: String) -> Double {
        let balance = accounts.first { $0.id == accountID }?.balance ?? 0
        return balance + positions.reduce(0) { $1.accountId == accountID ? $0 + $1.unrealizedPnl : $0 }
    }

    private func refreshAccounts() {
        let t = now
        var updated = accounts
        for index in updated.indices {
            let account = updated[index]
            guard account.kind.showsMoney else { updated[index].updatedAt = t; continue }
            let held = positions.filter { $0.accountId == account.id }
            let unrealized = held.reduce(0) { $0 + $1.unrealizedPnl }
            let waiting = orders.filter { $0.accountId == account.id && $0.status.isOpen && !$0.reduceOnly }
            let plan = plans.first { $0.accountId == account.id }
            let reserved = waiting.reduce(0) { $0 + ($1.price ?? 0) * $1.size / max(plan?.leverage ?? 1, 1) }
            let margin = held.reduce(0) { $0 + $1.margin } + reserved
            let equity = (account.balance ?? 0) + unrealized
            updated[index].equity = equity
            updated[index].unrealizedPnl = unrealized
            updated[index].marginUsed = margin
            updated[index].available = equity - margin
            updated[index].todayPnl = equity - (dayStartEquity[account.id] ?? equity)
            updated[index].todayFee = dayFee[account.id] ?? 0
            updated[index].updatedAt = t
        }
        accounts = updated
    }

    /// Mean-reversion-free momentum: the last price against the mean close of the last `bars` 5-minute bars.
    private func momentum(_ contract: String, bars count: Int) -> Double {
        guard let bars = series[contract]?[.m5]?.bars, !bars.isEmpty, let price = marks[contract] else { return 0 }
        let slice = bars.suffix(count)
        let mean = slice.reduce(0) { $0 + $1.c } / Double(slice.count)
        return mean > 0 ? price / mean - 1 : 0
    }

    private func refreshModels() {
        let t = now
        let fiveMinutes = 5 * Self.minute
        let todayStart = (t / Self.dayMs).rounded(.down) * Self.dayMs
        var updated = models
        for index in updated.indices {
            let status = updated[index]
            guard let account = account(id: status.accountId) else { continue }
            if account.kind.showsMoney {
                updated[index].lastRun = (t / fiveMinutes).rounded(.down) * fiveMinutes
                updated[index].nextRun = (updated[index].lastRun ?? t) + fiveMinutes
                var signals: [String: Double] = [:]
                for contract in status.contracts {
                    let name = String(contract.prefix(3))
                    signals[name + " mu_4h"] = momentum(contract, bars: 48)
                    signals[name + " mu_1d"] = momentum(contract, bars: 288)
                }
                signals["entry_thr"] = 0.004
                signals["exit_thr"] = 0.001
                updated[index].signals = signals
                let opens = fills.filter { $0.accountId == status.accountId && $0.model == status.model && $0.action == .open }
                updated[index].signalsTotal = opens.count
                updated[index].signalsToday = opens.filter { $0.t >= todayStart }.count
                let equity = max(account.equity ?? 1, 1)
                let marginShare = (account.marginUsed ?? 0) / equity
                let risk = positions.filter { $0.accountId == status.accountId && $0.model == status.model }
                    .map { abs($0.entryPx - ($0.stopPx ?? $0.entryPx)) * $0.size / equity }.max() ?? 0
                let todayShare = (account.todayPnl ?? 0) / equity
                updated[index].checks = [
                    LiveCheck(name: "行情新鲜", pass: true, detail: "延迟 1 秒"),
                    LiveCheck(name: "保证金占用 < 60%", pass: marginShare < 0.6, detail: BacktestFormat.plainPercent(marginShare)),
                    LiveCheck(name: "单笔风险 ≤ 1%", pass: risk <= 0.01, detail: BacktestFormat.plainPercent(risk, digits: 2)),
                    LiveCheck(name: "当日亏损未触线", pass: todayShare > -0.02, detail: BacktestFormat.percent(todayShare)),
                ]
            } else {
                let hourStart = (t / Self.hour).rounded(.down) * Self.hour
                updated[index].lastRun = status.state == .error ? hourStart - 3 * Self.hour : hourStart
                updated[index].nextRun = status.state == .error ? nil : hourStart + Self.hour
                updated[index].signals = [:]
                updated[index].checks = [
                    LiveCheck(name: "行情新鲜", pass: status.state != .error, detail: status.state == .error ? "延迟 7 分钟" : "延迟 1 秒"),
                    LiveCheck(name: "协议哈希一致", pass: true, detail: "1108cbff"),
                    LiveCheck(name: "封存未破", pass: true, detail: "结果 \(Self.shadowUnsealDate) 开封"),
                    LiveCheck(name: "与主线同源数据", pass: true),
                ]
            }
        }
        if updated != models { models = updated }
    }

    /// Shadow-ledger models emit a signal now and then; only the counts are ever shown.
    private func shadowSignals(at t: Double) {
        let hour = Int(t / Self.hour)
        guard hour != lastShadowHour else { return }
        lastShadowHour = hour
        let newDay = hour % 24 == 0
        var updated = models
        for index in updated.indices where updated[index].accountId == "shadow-1" {
            if newDay { updated[index].signalsToday = 0 }
            if updated[index].state == .running, rng.uniform() < 0.35 {
                updated[index].signalsToday += 1
                updated[index].signalsTotal += 1
            }
        }
        models = updated
    }
}
