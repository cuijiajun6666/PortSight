import SwiftUI
import PortSightKit

/// The icon rail, top to bottom, following the shared terminal sections (plan §0.1).
/// Settings stays in the toolbar and alerts live in the bell's notification panel, so neither has a rail item.
enum DesktopSection: String, CaseIterable, Identifiable {
    case overview, assets, trading, backtest, server, cloud, ai, remote

    var id: String { rawValue }
    private var terminal: TerminalSection { TerminalSection(rawValue: rawValue) ?? .overview }
    // 回测 is a Mac-only rail item; the shared TerminalSection (also used by iOS) has no case for it.
    var title: String { self == .backtest ? "回测" : terminal.title }
    var icon: String { self == .backtest ? "chart.line.text.clipboard" : terminal.icon }
    var selectedIcon: String { self == .backtest ? "chart.line.text.clipboard.fill" : terminal.selectedIcon }
    var subtitle: String { self == .backtest ? "量化系统跑完的回测，逐笔看进出场。" : terminal.subtitle }

    /// Tabs shown in the section's top bar, in groups separated by a gap. Empty means no bar.
    var tabGroups: [[DesktopTab]] {
        switch self {
        case .overview, .remote, .backtest: []
        case .assets: [[.allAssets, .usStocks, .crypto], [.positions, .orders, .market, .analysis, .activity]]
        case .trading: [[.live, .journal], [.reports, .strategies, .lines]]
        case .server: [[.serverStatus, .heartbeats, .jobs]]
        case .cloud: [[.photos, .upload, .storage, .transfer]]
        case .ai: [[.aiAsk, .aiDuty, .aiReview]]
        }
    }

    var defaultTab: DesktopTab? { tabGroups.first?.first }

    /// The account scope picker only applies to sections that show account money.
    var usesScope: Bool { self == .overview || self == .assets || self == .trading }
}

enum DesktopTab: Hashable, Identifiable {
    case allAssets, usStocks, crypto, positions, orders, market, analysis, activity
    case live, journal, reports, strategies, lines

    /// Pages built from cards (DesktopCard / DesktopMetricCard): every 资产 page and 交易 · 策略. Their cards sit
    /// straight on the window glass; the other pages lay sections on the white content panel.
    var isCardPage: Bool {
        switch self {
        case .allAssets, .usStocks, .crypto, .positions, .orders, .market, .analysis, .activity, .strategies: true
        default: false
        }
    }
    /// The 回测 section has no tab bar; this case is its deep link.
    case backtest
    case serverStatus, heartbeats, jobs
    case photos, upload, storage, transfer
    case aiAsk, aiDuty, aiReview

    var id: Self { self }

    var title: String {
        switch self {
        case .allAssets: "概览"
        case .usStocks: "美股"
        case .crypto: "加密"
        case .positions: "持仓"
        case .orders: "订单"
        case .market: "行情"
        case .analysis: "分析"
        case .activity: "动态"
        case .live: "实时"
        case .journal: "理由卡"
        case .lines: "线路"
        case .reports: "复盘"
        case .strategies: "策略"
        case .backtest: "回测"
        case .serverStatus: "概况"
        case .heartbeats: "心跳"
        case .jobs: "任务与队列"
        case .photos: "照片"
        case .upload: "上传"
        case .storage: "存储"
        case .transfer: "文件传输"
        case .aiAsk: "资料问答"
        case .aiDuty: "值班建议"
        case .aiReview: "每日复盘"
        }
    }

    var section: DesktopSection {
        switch self {
        case .allAssets, .usStocks, .crypto, .positions, .orders, .market, .analysis, .activity: .assets
        case .live, .journal, .lines, .reports, .strategies: .trading
        case .backtest: .backtest
        case .serverStatus, .heartbeats, .jobs: .server
        case .photos, .upload, .storage, .transfer: .cloud
        case .aiAsk, .aiDuty, .aiReview: .ai
        }
    }

    /// Links from the original asset pages (DesktopPage) land on the matching tab.
    init(page: DesktopPage) {
        switch page {
        case .overview: self = .allAssets
        case .positions: self = .positions
        case .market: self = .market
        case .orders: self = .orders
        case .analysis: self = .analysis
        case .strategies: self = .strategies
        case .activity: self = .activity
        }
    }
}

/// Asset class filter used by the 美股 / 加密 tabs.
enum DesktopAssetClass: Hashable {
    case all, usStocks, crypto

    func contains(_ kind: String) -> Bool {
        switch self {
        case .all: true
        case .usStocks: kind != "加密货币"
        case .crypto: kind == "加密货币"
        }
    }

    /// Type filters offered inside the holdings table for this class.
    var kinds: [String] {
        switch self {
        case .all: ["全部", "股票", "ETF", "加密货币"]
        case .usStocks: ["全部", "股票", "ETF"]
        case .crypto: []
        }
    }
}
