import Foundation

// This target is a visual prototype. Nothing here represents a real account or model forecast.
public enum PortfolioScope: String, CaseIterable, Identifiable {
    case all = "全部", personal = "个人", quant = "量化"
    public var id: String { rawValue }
    public var title: String { self == .all ? "Total Assets" : self == .personal ? "Personal Assets" : "Quant Assets" }
}
public struct DemoHolding: Identifiable {
    public let owner: PortfolioScope
    public let symbol, name, kind: String
    public let quantity, cost, price, previous: Double
    public var id: String { owner.rawValue + ":" + symbol }
    public var value: Double { quantity * price }
    public var pnl: Double { quantity * (price - cost) }
    public var dayPnL: Double { quantity * (price - previous) }

    public init(owner: PortfolioScope, symbol: String, name: String, kind: String, quantity: Double, cost: Double, price: Double, previous: Double) {
        self.owner = owner
        self.symbol = symbol
        self.name = name
        self.kind = kind
        self.quantity = quantity
        self.cost = cost
        self.price = price
        self.previous = previous
    }
}
public struct DemoActivity: Identifiable {
    public let id, title, detail, icon, time: String
    public let owner: PortfolioScope
    public let category: String
    public let amount: Double?

    public init(id: String, title: String, detail: String, icon: String, time: String, owner: PortfolioScope, category: String, amount: Double?) {
        self.id = id
        self.title = title
        self.detail = detail
        self.icon = icon
        self.time = time
        self.owner = owner
        self.category = category
        self.amount = amount
    }
}
public struct DemoNotice: Identifiable {
    public let id, title, detail, severity, category, time: String
    public let owner: PortfolioScope
    /// Set for a notice from the relay's GET /notices (RelayNotice.asNotice); the built-in notices leave them empty.
    public var fromRelay = false
    public var at: Date?
    /// The notice asks for 确认已查看 (relay notices say so; built-in ones do when critical).
    public var requiresAck = false
    /// Where its button leads (RelayLink); an unknown link is not offered.
    public var link: String?
    public var facts: [DemoNoticeFact] = []
    public var symbols: [String] = []
    public var expiresAt: Date?

    /// Waiting for 确认已查看: a relay notice that asks for it, or a built-in critical one; never once expired.
    public func needsAcknowledgement(now: Date = .now) -> Bool {
        if let expiresAt, expiresAt <= now { return false }
        return fromRelay ? requiresAck : severity == "critical"
    }

    public init(id: String, title: String, detail: String, severity: String, category: String, time: String, owner: PortfolioScope) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
        self.category = category
        self.time = time
        self.owner = owner
    }
}
public struct DemoNoticeFact: Hashable, Identifiable {
    public let label: String
    public let value: String
    public var id: String { label }

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct DemoPoint: Identifiable {
    public let id: Int
    public let date: Date
    public let equity, benchmark, drawdown: Double

    public init(id: Int, date: Date, equity: Double, benchmark: Double, drawdown: Double) {
        self.id = id
        self.date = date
        self.equity = equity
        self.benchmark = benchmark
        self.drawdown = drawdown
    }
}
public enum DemoPortfolioData {
    public static let enabled = true
    public static let date = Date(timeIntervalSince1970: 1_792_790_400) // Fixed demonstration timeline.
    public static let holdings: [DemoHolding] = [
        .init(owner: .personal, symbol: "NVDA", name: "NVIDIA", kind: "股票", quantity: 20, cost: 120, price: 140, previous: 137),
        .init(owner: .personal, symbol: "AAPL", name: "Apple", kind: "股票", quantity: 15, cost: 200, price: 220, previous: 218),
        .init(owner: .personal, symbol: "BTC", name: "Bitcoin", kind: "加密货币", quantity: 0.08, cost: 60000, price: 70000, previous: 69400),
        .init(owner: .personal, symbol: "ETH", name: "Ethereum", kind: "加密货币", quantity: 1.5, cost: 2800, price: 3000, previous: 2980),
        .init(owner: .quant, symbol: "NVDA", name: "NVIDIA", kind: "股票", quantity: 30, cost: 125, price: 140, previous: 137),
        .init(owner: .quant, symbol: "SPY", name: "S&P 500 ETF", kind: "ETF", quantity: 40, cost: 540, price: 580, previous: 578),
        .init(owner: .quant, symbol: "QQQ", name: "Nasdaq 100 ETF", kind: "ETF", quantity: 20, cost: 470, price: 500, previous: 497),
        .init(owner: .quant, symbol: "TLT", name: "Treasury Bond ETF", kind: "ETF", quantity: 50, cost: 98, price: 95, previous: 95.5)
    ]
    public static func lots(_ scope: PortfolioScope) -> [DemoHolding] { holdings.filter { scope == .all || $0.owner == scope } }
    public static func combined(_ scope: PortfolioScope) -> [DemoHolding] {
        Dictionary(grouping: lots(scope), by: \.symbol).values.map { group in
            let first = group[0], quantity = group.reduce(0) { $0 + $1.quantity }
            return DemoHolding(owner: scope, symbol: first.symbol, name: first.name, kind: first.kind,
                quantity: quantity, cost: group.reduce(0) { $0 + $1.quantity * $1.cost } / quantity,
                price: first.price, previous: first.previous)
        }.sorted { $0.value > $1.value }
    }
    public static func cash(_ scope: PortfolioScope) -> Double { scope == .all ? 22000 : scope == .personal ? 9000 : 13000 }
    public static func total(_ scope: PortfolioScope) -> Double { cash(scope) + lots(scope).reduce(0) { $0 + $1.value } }
    public static func pnl(_ scope: PortfolioScope) -> Double { lots(scope).reduce(0) { $0 + $1.pnl } }
    public static func principal(_ scope: PortfolioScope) -> Double { total(scope) - pnl(scope) }
    public static func dayPnL(_ scope: PortfolioScope) -> Double { lots(scope).reduce(0) { $0 + $1.dayPnL } }
    public static func points(_ scope: PortfolioScope) -> [DemoPoint] {
        let personal = singlePoints(.personal), quant = singlePoints(.quant)
        let values = (0..<30).map { i in scope == .all ? personal[i] + quant[i] : scope == .personal ? personal[i] : quant[i] }
        var peak = values[0]
        return values.enumerated().map { i, value in
            peak = max(peak, value)
            return DemoPoint(id: i, date: date.addingTimeInterval(Double(i - 29) * 86400), equity: value,
                benchmark: principal(scope) * (1 + Double(i) / 29 * 0.038), drawdown: (peak - value) / peak)
        }
    }
    private static func singlePoints(_ scope: PortfolioScope) -> [Double] {
        (0..<30).map { i in
            let progress = Double(i) / 29
            let wave = sin(Double(i) * 0.72) * (scope == .personal ? 360.0 : 520.0) * sin(progress * .pi)
            return principal(scope) + pnl(scope) * progress + wave
        }
    }
    public static let activities: [DemoActivity] = [
        .init(id: "a1", title: "买入 NVDA", detail: "量化选股 · 10 股 × $140.00", icon: "arrow.down.left", time: "今天 10:32", owner: .quant, category: "成交", amount: -1400),
        .init(id: "a2", title: "内部资金划转", detail: "个人 → 量化 · 不计入投资收益", icon: "arrow.left.arrow.right", time: "今天 09:45", owner: .all, category: "资金", amount: 2000),
        .init(id: "a3", title: "买入 AAPL", detail: "个人交易 · 5 股 × $220.00", icon: "arrow.down.left", time: "昨天 14:20", owner: .personal, category: "成交", amount: -1100),
        .init(id: "a4", title: "SPY 分红到账", detail: "核心 ETF 组合 · 现金分红", icon: "dollarsign.arrow.circlepath", time: "昨天 11:00", owner: .quant, category: "分红", amount: 64),
        .init(id: "a5", title: "趋势策略完成检查", detail: "维持现有仓位 · 无需调仓", icon: "checkmark.circle", time: "昨天 09:35", owner: .quant, category: "系统", amount: nil),
        .init(id: "a6", title: "银行入金", detail: "个人账户 · 资金流入，不计入收益", icon: "building.columns", time: "10 月 20 日", owner: .personal, category: "资金", amount: 1000)
    ]
    public static let notices: [DemoNotice] = [
        .init(id: "n1", title: "量化账户触发保护检查", detail: "出现异常报价，相关调仓已暂缓。确认仅表示已读，不会解除系统保护。", severity: "critical", category: "安全", time: "10:34", owner: .quant),
        .init(id: "n2", title: "NVDA 合并敞口提醒", detail: "个人持有 20 股，量化持有 30 股。合并持有 50 股，请同时查看两部分来源。", severity: "warning", category: "风险", time: "10:33", owner: .all),
        .init(id: "n3", title: "AAPL 近期财报事件", detail: "财报将在下周公布，留意盘后波动。", severity: "info", category: "事件", time: "09:00", owner: .personal),
        .init(id: "n4", title: "每日复盘已生成", detail: "资产、基准、回撤和交易成本的复盘已可查看。", severity: "info", category: "复盘", time: "昨天 21:00", owner: .all)
    ]
}
