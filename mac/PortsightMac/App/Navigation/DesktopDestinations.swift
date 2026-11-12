import SwiftUI
import PortSightKit
enum DesktopPage: String, CaseIterable, Identifiable {
    case overview = "资产总览", positions = "全部持仓", market = "市场行情"
    case orders = "订单记录", analysis = "组合分析", strategies = "量化策略", activity = "账户动态"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .positions: "chart.pie"
        case .market: "waveform.path.ecg.rectangle"
        case .orders: "list.bullet.rectangle"
        case .analysis: "chart.bar"
        case .strategies: "cpu"
        case .activity: "clock"
        }
    }
    // Every navigation symbol has a real filled counterpart, not just a tint change.
    var selectedIcon: String { icon + ".fill" }

    var subtitle: String {
        switch self {
        case .overview: "让每一份资产，都清晰可见。"
        case .positions: "股票、ETF 与加密货币，一处掌握。"
        case .market: "关注市场，也关注你的下一步。"
        case .orders: "每一笔交易，都有迹可循。"
        case .analysis: "看见收益背后的配置与风险。"
        case .strategies: "策略运行、模型表现与风险监控。"
        case .activity: "交易、资金和系统动态的完整时间线。"
        }
    }
}

enum DesktopSheet: String, Identifiable {
    case settings, report, fullAnalysis, strategy
    var id: String { rawValue }
    var title: String {
        switch self {
        case .settings: "偏好设置"
        case .report: "收益复盘"
        case .fullAnalysis: "详细分析"
        case .strategy: "策略详情"
        }
    }
}

