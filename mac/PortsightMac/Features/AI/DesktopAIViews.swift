import SwiftUI
import PortSightKit

/// AI: the private AI server's three services. None is connected yet: the server has no read-only app token.
struct DesktopAIView: View {
    let tab: DesktopTab

    private var service: AIService {
        let id = tab == .aiAsk ? "qa" : tab == .aiDuty ? "duty" : "review"
        return DemoTerminalData.aiServices.first { $0.id == id } ?? DemoTerminalData.aiServices[0]
    }

    var body: some View {
        DesktopFullPage(maxWidth: 900) {
            DesktopPageHeader(eyebrow: "私有 AI 服务器", title: service.title, detail: service.detail) {
                DesktopPendingLabel()
            }
            // The built-in suggestions and review, paired or not (the relay has no AI source yet).
            switch tab {
            case .aiDuty: duty
            case .aiReview: review
            default: ask
            }
            Text("AI 服务器还没有给 App 的只读令牌，App 不保存管理员密码。")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }

    private var ask: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass").foregroundStyle(.secondary)
                TextField("问问自己的笔记、研报和代码…", text: .constant(""))
                    .textFieldStyle(.plain).font(.system(size: 15))
                    .disabled(true)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .glassEffect(.regular, in: Capsule())
            DesktopPageSection(title: "可以这样问") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(["19b 订单流集成用了哪些特征？", "上周股票模拟盘为什么跑赢 SPY？", "forward15m 采集器以前出过什么问题？"], id: \.self) { prompt in
                        Label(prompt, systemImage: "text.bubble").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var duty: some View {
        DesktopPageSection(title: "下一步建议", subtitle: "读告警和心跳生成 · 只给建议，不执行", showsDivider: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(DemoTerminalData.aiSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                    if index > 0 { Divider().opacity(0.5) }
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: suggestion.category.icon).font(.system(size: 15)).foregroundStyle(DesktopTheme.blue).frame(width: 22)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(suggestion.title).font(.system(size: 14, weight: .semibold))
                            Text(suggestion.reason).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        DesktopPill(text: suggestion.category.title, color: .secondary)
                    }
                    .padding(.vertical, 14)
                }
            }
        }
    }

    private var review: some View {
        let review = DemoTerminalData.review
        return DesktopPageSection(title: review.headline,
                                  subtitle: review.date.formatted(date: .complete, time: .shortened), showsDivider: false) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(review.points, id: \.self) { point in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(.secondary).frame(width: 4, height: 4)
                        Text(point).font(.system(size: 14))
                    }
                }
            }
        }
    }
}

/// 远程: Jump Desktop first, Screen Sharing as the fallback, plus the browser consoles.
struct DesktopRemoteView: View {
    private var primary: RemoteEntry { DemoTerminalData.remoteEntries.first(where: \.isPrimary)! }
    private var others: [RemoteEntry] { DemoTerminalData.remoteEntries.filter { !$0.isPrimary } }

    var body: some View {
        DesktopFullPage(maxWidth: 900) {
            DesktopPageHeader(eyebrow: "远程", title: "回到 Mac mini 的桌面", detail: "只打开对应的 App；App 自己不实现远程桌面协议。")
            HStack(alignment: .center, spacing: 22) {
                Image(systemName: primary.icon).font(.system(size: 34, weight: .light)).foregroundStyle(DesktopTheme.blue)
                    .frame(width: 72, height: 72)
                    .background(DesktopTheme.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(primary.title).font(.system(size: 19, weight: .semibold))
                        DesktopPill(text: "首选")
                    }
                    Text(primary.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(primary.address).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                }
                Spacer()
                Button {} label: { Label("连接", systemImage: "play.fill") }
                    .buttonStyle(.glassProminent).controlSize(.large)
                    .disabled(true).help("Mac mini 到位并装好 Jump Desktop Connect 后可用")
            }
            DesktopPageSection(title: "其他入口") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(others.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().opacity(0.5).padding(.leading, 44) }
                        HStack(spacing: 14) {
                            Image(systemName: entry.icon).font(.system(size: 17)).foregroundStyle(.secondary).frame(width: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.title).font(.system(size: 14, weight: .semibold))
                                Text(entry.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.address).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                            Button("打开") {}.buttonStyle(.glass).disabled(true)
                        }
                        .padding(.vertical, 13)
                    }
                }
            }
            DesktopPageSection(title: "提示") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("两台都是 Apple 芯片且 macOS 14 以上时，屏幕共享可以选「高性能」模式。", systemImage: "bolt")
                    Label("UU 远程只作应急备用，平时保持关闭。", systemImage: "lifepreserver")
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}
