import Foundation

/// Fictional market fixtures. No live news, economic calendar or fund-flow feed.
public enum DemoMarketContext {
    // A session-relative clock keeps the prototype countdown useful on every launch.
    public static let referenceDate = Date()

    public static let sectorFlows: [SectorMoneyFlow] = [
        .init(id: "semiconductors", name: "半导体", netInflow: 2.46),
        .init(id: "software", name: "软件", netInflow: 1.38),
        .init(id: "financials", name: "金融", netInflow: 0.86),
        .init(id: "healthcare", name: "医疗", netInflow: 0.42),
        .init(id: "consumer", name: "消费", netInflow: -0.93),
        .init(id: "energy", name: "能源", netInflow: -0.71),
        .init(id: "industrials", name: "工业", netInflow: 0.28),
        .init(id: "utilities", name: "公用事业", netInflow: -0.16)
    ]

    public static let events: [MarketCalendarEvent] = [
        .init(id: "apple-results", title: "Apple 财报发布", category: "公司财报",
              date: referenceDate.addingTimeInterval(2 * 86_400 + 6 * 3_600 + 30 * 60), symbols: ["AAPL"]),
        .init(id: "rate-decision", title: "美联储利率决议", category: "宏观事件",
              date: referenceDate.addingTimeInterval(3 * 86_400 + 8 * 3_600), symbols: []),
        .init(id: "nvidia-results", title: "NVIDIA 财报发布", category: "公司财报",
              date: referenceDate.addingTimeInterval(5 * 86_400 + 4 * 3_600), symbols: ["NVDA"])
    ]

    public static let news: [RelatedMarketNews] = [
        .init(id: "chip-demand", title: "AI 算力需求与半导体板块关注度升温",
              summary: "云厂商上调资本开支，数据中心芯片订单排到明年，NVDA 与 QQQ 中的半导体权重受益。",
              symbols: ["NVDA", "QQQ"], publishedAt: referenceDate.addingTimeInterval(-12 * 60)),
        .init(id: "apple-preview", title: "财报前瞻：关注 Apple 的业务表现与指引",
              summary: "市场关注服务业务增速和下季度毛利率指引，期权隐含波动率较上周走高。",
              symbols: ["AAPL"], publishedAt: referenceDate.addingTimeInterval(-35 * 60)),
        .init(id: "crypto-flows", title: "数字资产市场：资金与流动性观察",
              summary: "现货 ETF 连续净流入，资金费率回落到中性区间，短线杠杆有所降温。",
              symbols: ["BTC", "ETH"], publishedAt: referenceDate.addingTimeInterval(-52 * 60)),
        .init(id: "macro-watch", title: "本周宏观观察：利率预期与资产配置",
              summary: "降息预期小幅后移，美债收益率上行，成长股估值短期承压。",
              symbols: [], publishedAt: referenceDate.addingTimeInterval(-75 * 60))
    ]

    public static func events(for scope: PortfolioScope) -> [MarketCalendarEvent] {
        let heldSymbols = Set(DemoPortfolioData.combined(scope).map(\.symbol))
        return events.filter { $0.symbols.isEmpty || !$0.symbols.isDisjoint(with: heldSymbols) }
            .sorted { $0.date < $1.date }
    }

    public static func nextEvent(for scope: PortfolioScope, after date: Date) -> MarketCalendarEvent? {
        events(for: scope).first { $0.date >= date }
    }

    public static func news(for scope: PortfolioScope) -> [RelatedMarketNews] {
        let heldSymbols = Set(DemoPortfolioData.combined(scope).map(\.symbol))
        return news.filter { $0.symbols.isEmpty || !$0.symbols.isDisjoint(with: heldSymbols) }
            .sorted { $0.publishedAt > $1.publishedAt }
    }
}
