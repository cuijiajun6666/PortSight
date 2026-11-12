//
//  BacktestSample.swift
//  PortSight
//
//  A built-in sample in the exported format, for building the viewer before the quant system hands over its
//  sample directory (§四.1). Prices are a seeded random walk shaped like 2020–2022 BTC / ETH; the trades come
//  from a simple EMA rule with trailing stops, so they show every feature of the page: stair-step stops and
//  targets, adds, reductions, partial take-profits, every exit reason and quick re-entries. Nothing here is a
//  real strategy result.
//

import Foundation

public enum BacktestSample {
    private static let start = 1_583_020_800_000.0   // 2020-03-01 UTC
    private static let end = 1_672_444_800_000.0     // 2022-12-31 UTC
    private static let hour = 3_600_000.0

    struct Params {
        let entry: Double
        let exit: Double
        let stopATR: Double
        let targetATR: Double?
        let allowShort: Bool
        let maxHoldH: Double
    }

    private struct Market {
        let symbol: String
        let hourly: [BacktestBar]
        let emaFast: [Double]
        let emaSlow: [Double]
        let emaDay: [Double]
        let atr: [Double]
    }

    /// The sample runs: the selected point, a rejected neighbour and a baseline, all on the same prices.
    public static func runs() -> [BacktestRun] {
        let markets = [market("BTCUSDT", from: 8_520, sigma: 0.0058, seed: 7),
                       market("ETHUSDT", from: 231, sigma: 0.0074, seed: 11)]
        return [
            run(BacktestMeta(runID: "g263_ema1h_vol10", strategy: "v4 arm0 G263", protocolSHA: "1108cbff9a2e47d0",
                             segment: "discovery", start: start, end: end, verdict: "selected (discovery only)",
                             costModel: "taker 5bp + slippage", notes: "收益集中在 2022"),
                params: Params(entry: 0.011, exit: 0.002, stopATR: 2.6, targetATR: nil, allowShort: true, maxHoldH: 480),
                markets: markets, seed: 263),
            run(BacktestMeta(runID: "g210_ema1h", strategy: "v4 arm0 G210", protocolSHA: "1108cbff9a2e47d0",
                             segment: "discovery", start: start, end: end, verdict: "rejected (discovery)",
                             costModel: "taker 5bp + slippage", notes: "止损偏近，常被插针扫掉"),
                params: Params(entry: 0.008, exit: 0.003, stopATR: 1.4, targetATR: 3.2, allowShort: true, maxHoldH: 160),
                markets: markets, seed: 210),
            run(BacktestMeta(runID: "rule_h_baseline", strategy: "规则 H", protocolSHA: "1108cbff9a2e47d0",
                             segment: "discovery", start: start, end: end, verdict: "report only",
                             costModel: "taker 5bp + slippage", notes: "对照组：只做多，固定止盈"),
                params: Params(entry: 0.014, exit: 0.0, stopATR: 2.0, targetATR: 4.0, allowShort: false, maxHoldH: 240),
                markets: markets, seed: 8),
        ]
    }

    // MARK: Prices

    private static func market(_ symbol: String, from first: Double, sigma: Double, seed: UInt64) -> Market {
        var rng = SplitMix(seed)
        var bars: [BacktestBar] = []
        bars.reserveCapacity(Int((end - start) / hour))
        var price = first
        var t = start
        while t < end {
            // Up through 2021, down in 2022, with slow regime swings and the odd wick.
            let year = (t - start) / (365 * 24 * hour)
            let drift = (year < 1.75 ? 0.00011 : -0.00009) + 0.00008 * sin(t / (40 * 24 * hour))
            let shock = rng.normal() * sigma * (1 + 0.6 * sin(t / (90 * 24 * hour)))
            let open = price
            let close = open * exp(drift + shock)
            let wick = rng.uniform() < 0.004 ? 4.0 : 1.0
            let high = max(open, close) * (1 + abs(rng.normal()) * sigma * 0.45 * wick)
            let low = min(open, close) * (1 - abs(rng.normal()) * sigma * 0.45 * wick)
            bars.append(BacktestBar(t: t, o: open, h: high, l: low, c: close, v: 800 + rng.uniform() * 1_600))
            price = close
            t += hour
        }
        let closes = bars.map(\.c)
        var atr: [Double] = []
        var value = 0.0
        for (index, bar) in bars.enumerated() {
            let previous = index > 0 ? bars[index - 1].c : bar.o
            let range = max(bar.h - bar.l, abs(bar.h - previous), abs(bar.l - previous))
            value = index == 0 ? range : value + (range - value) / 24
            atr.append(value)
        }
        return Market(symbol: symbol, hourly: bars, emaFast: ema(closes, 12), emaSlow: ema(closes, 48),
                      emaDay: ema(closes, 96), atr: atr)
    }

    private static func ema(_ values: [Double], _ period: Double) -> [Double] {
        let k = 2 / (period + 1)
        var out: [Double] = []
        out.reserveCapacity(values.count)
        var current = values.first ?? 0
        for value in values {
            current += (value - current) * k
            out.append(current)
        }
        return out
    }

    private static func aggregate(_ bars: [BacktestBar], _ timeframe: BacktestTimeframe) -> [BacktestBar] {
        let span = timeframe.seconds * 1_000
        var out: [BacktestBar] = []
        var bucket: [BacktestBar] = []
        func flush() {
            guard let first = bucket.first, let last = bucket.last else { return }
            out.append(BacktestBar(t: (first.t / span).rounded(.down) * span, o: first.o,
                                   h: bucket.map(\.h).max() ?? first.h, l: bucket.map(\.l).min() ?? first.l,
                                   c: last.c, v: bucket.map(\.v).reduce(0, +)))
            bucket.removeAll(keepingCapacity: true)
        }
        for bar in bars {
            if let first = bucket.first, (bar.t / span).rounded(.down) != (first.t / span).rounded(.down) { flush() }
            bucket.append(bar)
        }
        flush()
        return out
    }

    /// Four 15-minute bars inside each hour, touching that hour's high and low.
    private static func quarterHours(_ bars: [BacktestBar], seed: UInt64) -> [BacktestBar] {
        var rng = SplitMix(seed)
        var out: [BacktestBar] = []
        out.reserveCapacity(bars.count * 4)
        for bar in bars {
            let highAt = Int(rng.uniform() * 4) % 4
            var lowAt = Int(rng.uniform() * 4) % 4
            if lowAt == highAt { lowAt = (lowAt + 2) % 4 }
            var open = bar.o
            for part in 0..<4 {
                let close = part == 3 ? bar.c
                    : min(bar.h, max(bar.l, bar.o + (bar.c - bar.o) * Double(part + 1) / 4 + rng.normal() * (bar.h - bar.l) * 0.15))
                let high = part == highAt ? bar.h : min(bar.h, max(open, close) + (bar.h - max(open, close)) * rng.uniform() * 0.5)
                let low = part == lowAt ? bar.l : max(bar.l, min(open, close) - (min(open, close) - bar.l) * rng.uniform() * 0.5)
                out.append(BacktestBar(t: bar.t + Double(part) * 900_000, o: open, h: high, l: low, c: close, v: bar.v / 4))
                open = close
            }
        }
        return out
    }

    // MARK: Trades

    private static func signal(_ market: Market, _ i: Int) -> (mu4h: Double, mu1d: Double) {
        (market.emaFast[i] / market.emaSlow[i] - 1, market.hourly[i].c / market.emaDay[i] - 1)
    }

    private static func run(_ meta: BacktestMeta, params: Params, markets: [Market], seed: UInt64) -> BacktestRun {
        var rng = SplitMix(seed)
        var trades: [BacktestTrade] = []
        for market in markets {
            trades += simulate(market, params: params, rng: &rng, idPrefix: meta.runID.prefix(4).uppercased())
        }
        trades.sort { $0.entryT < $1.entryT }
        let equity = equityCurve(trades, benchmark: markets[0].hourly)
        let bySymbol = Dictionary(uniqueKeysWithValues: markets.map { ($0.symbol, $0) })
        var derived: [String: [BacktestBar]] = [:]
        return BacktestRun(
            meta: meta, trades: trades, equity: equity, symbols: markets.map(\.symbol),
            bars: { symbol, timeframe in
                guard let market = bySymbol[symbol] else { return [] }
                let key = symbol + timeframe.rawValue
                if let cached = derived[key] { return cached }
                let bars: [BacktestBar] = switch timeframe {
                case .h1: market.hourly
                case .h4, .d1: aggregate(market.hourly, timeframe)
                case .m15: quarterHours(market.hourly, seed: seed &+ 15)
                case .m1, .m5: []
                }
                derived[key] = bars
                return bars
            },
            signals: { symbol in
                guard let market = bySymbol[symbol] else { return [] }
                return market.hourly.indices.map { i in
                    let s = signal(market, i)
                    return BacktestSignalPoint(t: market.hourly[i].t,
                                               values: ["mu_4h": s.mu4h, "mu_1d": s.mu1d,
                                                        "entry_thr": params.entry, "exit_thr": params.exit])
                }
            })
    }

    private static func simulate(_ market: Market, params: Params, rng: inout SplitMix, idPrefix: String) -> [BacktestTrade] {
        let bars = market.hourly
        var trades: [BacktestTrade] = []
        var i = 120
        var number = 0
        while i < bars.count - 2 {
            let s = signal(market, i)
            let side: BacktestSide? = s.mu4h > params.entry ? .long
                : (params.allowShort && s.mu4h < -params.entry ? .short : nil)
            guard let side else { i += 1; continue }

            let entryBar = bars[i + 1]
            let entryPx = entryBar.o
            let sign = side.sign
            var stop = entryPx - sign * params.stopATR * market.atr[i]
            let target = params.targetATR.map { entryPx + sign * $0 * market.atr[i] }
            var stops = [BacktestLevel(t: entryBar.t, px: stop)]
            var targets = target.map { [BacktestLevel(t: entryBar.t, px: $0)] } ?? []
            var sizes = [BacktestSizeStep(t: entryBar.t, w: sign * 0.05, why: "open")]
            var weight = 0.05, added = false, reduced = false, partial = false
            var weightHours = 0.0, best = 0.0, worst = 0.0, funding = 0.0
            var exitPx = entryPx, exitT = entryBar.t, reason = "time_exit"
            var j = i + 1
            while j < bars.count {
                let bar = bars[j]
                // Stops and targets inside the bar first.
                if sign > 0 ? bar.l <= stop : bar.h >= stop {
                    exitPx = stop; exitT = bar.t + 2_400_000; reason = "stop_loss"; break
                }
                if let current = targets.last?.px, sign > 0 ? bar.h >= current : bar.l <= current {
                    exitPx = current; exitT = bar.t + 2_400_000; reason = "take_profit"; break
                }
                weightHours += weight
                best = max(best, sign * ((sign > 0 ? bar.h : bar.l) / entryPx - 1))
                worst = min(worst, sign * ((sign > 0 ? bar.l : bar.h) / entryPx - 1))
                if Int((bar.t - entryBar.t) / hour) % 8 == 7 { funding -= sign * weight * 0.0001 }

                let close = bar.c
                let atr = market.atr[j]
                let mu = signal(market, j).mu4h * sign
                let held = (bar.t + hour - entryBar.t) / hour
                let gain = sign * (close / entryPx - 1)

                // Trail the stop every 12 hours, only ever tighter.
                if Int(held) % 12 == 0 {
                    let trailed = close - sign * params.stopATR * atr
                    if sign * (trailed - stop) > atr * 0.15 {
                        stop = trailed
                        stops.append(BacktestLevel(t: bar.t + hour, px: stop))
                    }
                }
                if let base = target, Int(held) % 48 == 0, mu > params.entry * 1.6 {
                    let raised = base + sign * atr * (Double(targets.count) * 0.8)
                    targets.append(BacktestLevel(t: bar.t + hour, px: raised))
                }
                if !added && gain > 1.2 * atr / entryPx {
                    weight = 0.08; added = true
                    sizes.append(BacktestSizeStep(t: bar.t + hour, w: sign * weight, why: "add"))
                } else if let current = targets.last?.px, !partial, sign * (close - entryPx) > 0.5 * abs(current - entryPx) {
                    weight *= 0.5; partial = true
                    sizes.append(BacktestSizeStep(t: bar.t + hour, w: sign * weight, why: "partial_tp"))
                } else if added && !reduced && mu < (params.entry + params.exit) / 2 {
                    weight = 0.04; reduced = true
                    sizes.append(BacktestSizeStep(t: bar.t + hour, w: sign * weight, why: "reduce"))
                }

                if mu < -params.entry {
                    exitPx = close; exitT = bar.t + hour; reason = "signal_reverse"; break
                }
                if mu < params.exit {
                    exitPx = close; exitT = bar.t + hour; reason = "signal_exit"; break
                }
                if atr / close > 0.022 {
                    exitPx = close; exitT = bar.t + hour; reason = "risk_cut"; break
                }
                if held >= params.maxHoldH {
                    exitPx = close; exitT = bar.t + hour; reason = "time_exit"; break
                }
                j += 1
            }
            if j >= bars.count { break }

            let holdH = max((exitT - entryBar.t) / hour, 0.25)
            let averageWeight = weightHours > 0 ? weightHours / max(holdH.rounded(.down), 1) : weight
            let gross = averageWeight * sign * (exitPx / entryPx - 1)
            var turnover = 0.0, previous = 0.0
            for step in sizes { turnover += abs(step.w - previous); previous = step.w }
            turnover += abs(previous)
            let fee = turnover * 0.0007
            number += 1
            let s0 = signal(market, i)
            trades.append(BacktestTrade(
                id: idPrefix + "-" + market.symbol.prefix(3) + String(format: "%04d", number),
                symbol: market.symbol, side: side, entryT: entryBar.t, entryPx: entryPx,
                exitT: exitT, exitPx: exitPx, exitReason: reason, sizePath: sizes, stops: stops, targets: targets,
                pnlGross: gross, fee: fee, funding: funding, pnlNet: gross - fee + funding,
                mfe: best * averageWeight, mae: worst * averageWeight, holdH: holdH,
                signalsAtEntry: ["mu_4h": s0.mu4h, "mu_1d": s0.mu1d, "hold_value": min(1, max(0, 0.5 + s0.mu4h * 30))]))

            // Usually wait a little; sometimes go straight back in (平了又开).
            let exitIndex = min(bars.count - 1, Int((exitT - start) / hour))
            i = exitIndex + (rng.uniform() < 0.25 ? 0 : 2 + Int(rng.uniform() * 10))
        }
        return trades
    }

    private static func equityCurve(_ trades: [BacktestTrade], benchmark: [BacktestBar]) -> [BacktestEquityPoint] {
        let day = 24 * hour
        var realised: [Int: Double] = [:]
        for trade in trades { realised[Int(trade.exitT / day), default: 0] += trade.pnlNet }
        var closes: [Int: Double] = [:]
        for bar in benchmark { closes[Int(bar.t / day)] = bar.c }
        let firstClose = benchmark.first?.c ?? 1
        var nav = 1.0, peak = 1.0
        var points: [BacktestEquityPoint] = []
        var key = Int(start / day)
        while Double(key) * day < end {
            nav *= 1 + (realised[key] ?? 0)
            peak = max(peak, nav)
            points.append(BacktestEquityPoint(t: Double(key) * day, nav: nav, dd: nav / peak - 1,
                                              benchNav: closes[key].map { $0 / firstClose }))
            key += 1
        }
        return points
    }
}

/// Small deterministic generator, so the sample is the same on every launch.
nonisolated struct SplitMix {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func normal() -> Double {
        let u = max(uniform(), 1e-12)
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * uniform())
    }
}
