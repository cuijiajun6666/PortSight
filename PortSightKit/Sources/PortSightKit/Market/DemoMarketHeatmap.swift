import Foundation

/// Fixed US-stock heatmap fixtures: approximate market caps (USD billions), a made-up session's day change
/// and net money flow (USD millions). No market data feed. NVDA and AAPL match the built-in holdings.
public enum DemoMarketHeatmap {
    private static func s(_ symbol: String, _ name: String, cap: Double, price: Double, change: Double, flow: Double) -> HeatmapStock {
        HeatmapStock(symbol: symbol, name: name, marketCap: cap, price: price, change: change / 100, netFlow: flow)
    }

    public static let sectors: [HeatmapSector] = [
        HeatmapSector(id: "semiconductors", name: "半导体", stocks: [
            s("NVDA", "NVIDIA", cap: 4_400, price: 140, change: 2.19, flow: 1_240),
            s("AVGO", "Broadcom", cap: 1_600, price: 342.10, change: 1.86, flow: 520),
            s("TSM", "台积电", cap: 1_500, price: 289.40, change: 1.12, flow: 310),
            s("AMD", "AMD", cap: 380, price: 233.60, change: 3.42, flow: 460),
            s("MU", "Micron", cap: 220, price: 196.80, change: 2.71, flow: 180),
            s("QCOM", "Qualcomm", cap: 180, price: 164.30, change: -0.42, flow: -35),
            s("INTC", "Intel", cap: 180, price: 41.20, change: -1.85, flow: -140),
            s("TXN", "Texas Instruments", cap: 150, price: 165.70, change: -0.66, flow: -42)
        ]),
        HeatmapSector(id: "software", name: "软件", stocks: [
            s("MSFT", "Microsoft", cap: 3_800, price: 508.20, change: 0.74, flow: 380),
            s("ORCL", "Oracle", cap: 700, price: 248.90, change: 2.35, flow: 290),
            s("PLTR", "Palantir", cap: 420, price: 178.40, change: 4.12, flow: 410),
            s("CRM", "Salesforce", cap: 240, price: 249.60, change: -0.95, flow: -70),
            s("NOW", "ServiceNow", cap: 190, price: 915.30, change: 0.38, flow: 22),
            s("INTU", "Intuit", cap: 180, price: 648.20, change: -0.21, flow: -12),
            s("ADBE", "Adobe", cap: 150, price: 352.70, change: -1.48, flow: -95)
        ]),
        HeatmapSector(id: "hardware", name: "科技硬件", stocks: [
            s("AAPL", "Apple", cap: 3_900, price: 220, change: 0.92, flow: 260),
            s("IBM", "IBM", cap: 280, price: 301.50, change: -0.36, flow: -18),
            s("CSCO", "Cisco", cap: 270, price: 68.40, change: 0.29, flow: 15),
            s("DELL", "Dell", cap: 90, price: 132.80, change: 1.64, flow: 38)
        ]),
        HeatmapSector(id: "internet", name: "互联网", stocks: [
            s("GOOGL", "Alphabet", cap: 3_100, price: 256.30, change: 1.27, flow: 420),
            s("META", "Meta", cap: 1_800, price: 712.40, change: -0.58, flow: -160),
            s("NFLX", "Netflix", cap: 480, price: 1_118.00, change: 0.83, flow: 54),
            s("UBER", "Uber", cap: 200, price: 95.60, change: -1.22, flow: -48)
        ]),
        HeatmapSector(id: "discretionary", name: "可选消费", stocks: [
            s("AMZN", "Amazon", cap: 2_400, price: 226.10, change: -0.47, flow: -210),
            s("TSLA", "Tesla", cap: 1_400, price: 436.80, change: -2.86, flow: -620),
            s("HD", "Home Depot", cap: 380, price: 381.20, change: 0.31, flow: 14),
            s("MCD", "McDonald's", cap: 220, price: 304.50, change: -0.18, flow: -8),
            s("NKE", "Nike", cap: 95, price: 64.30, change: -2.14, flow: -66)
        ]),
        HeatmapSector(id: "staples", name: "必需消费", stocks: [
            s("WMT", "Walmart", cap: 800, price: 100.40, change: 0.44, flow: 46),
            s("COST", "Costco", cap: 420, price: 942.70, change: -0.62, flow: -38),
            s("PG", "Procter & Gamble", cap: 360, price: 152.90, change: -0.27, flow: -16),
            s("KO", "Coca-Cola", cap: 300, price: 69.80, change: 0.15, flow: 6),
            s("PEP", "PepsiCo", cap: 200, price: 146.10, change: -0.83, flow: -28)
        ]),
        HeatmapSector(id: "financials", name: "金融", stocks: [
            s("BRK.B", "Berkshire Hathaway", cap: 1_050, price: 486.20, change: 0.21, flow: 34),
            s("JPM", "JPMorgan", cap: 850, price: 309.40, change: 1.08, flow: 190),
            s("V", "Visa", cap: 680, price: 346.70, change: 0.56, flow: 62),
            s("MA", "Mastercard", cap: 530, price: 574.10, change: 0.49, flow: 41),
            s("BAC", "Bank of America", cap: 390, price: 51.80, change: 1.37, flow: 88),
            s("WFC", "Wells Fargo", cap: 270, price: 84.60, change: 1.62, flow: 70),
            s("GS", "Goldman Sachs", cap: 240, price: 790.30, change: 2.05, flow: 96)
        ]),
        HeatmapSector(id: "healthcare", name: "医疗", stocks: [
            s("LLY", "Eli Lilly", cap: 900, price: 951.20, change: -1.34, flow: -230),
            s("JNJ", "Johnson & Johnson", cap: 460, price: 191.40, change: 0.36, flow: 24),
            s("ABBV", "AbbVie", cap: 400, price: 226.80, change: 0.71, flow: 37),
            s("UNH", "UnitedHealth", cap: 300, price: 331.60, change: -2.47, flow: -150),
            s("MRK", "Merck", cap: 240, price: 95.90, change: -0.52, flow: -21),
            s("PFE", "Pfizer", cap: 145, price: 25.60, change: -0.98, flow: -19)
        ]),
        HeatmapSector(id: "industrials", name: "工业", stocks: [
            s("GE", "GE Aerospace", cap: 320, price: 301.70, change: 1.18, flow: 58),
            s("CAT", "Caterpillar", cap: 270, price: 574.30, change: 0.88, flow: 44),
            s("RTX", "RTX", cap: 220, price: 164.20, change: 0.24, flow: 9),
            s("BA", "Boeing", cap: 160, price: 211.50, change: -1.06, flow: -52),
            s("UNP", "Union Pacific", cap: 135, price: 226.40, change: -0.31, flow: -7),
            s("HON", "Honeywell", cap: 130, price: 205.10, change: -0.12, flow: -4)
        ]),
        HeatmapSector(id: "energy", name: "能源", stocks: [
            s("XOM", "Exxon Mobil", cap: 480, price: 114.20, change: -1.42, flow: -180),
            s("CVX", "Chevron", cap: 310, price: 154.60, change: -1.17, flow: -110),
            s("COP", "ConocoPhillips", cap: 115, price: 90.30, change: -2.03, flow: -64)
        ]),
        HeatmapSector(id: "utilities", name: "公用事业", stocks: [
            s("NEE", "NextEra Energy", cap: 165, price: 80.10, change: -0.34, flow: -12),
            s("SO", "Southern", cap: 100, price: 91.70, change: 0.18, flow: 4),
            s("DUK", "Duke Energy", cap: 95, price: 122.40, change: -0.09, flow: -2)
        ])
    ]

    public static var stocks: [HeatmapStock] { sectors.flatMap(\.stocks) }
}
