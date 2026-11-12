import SwiftUI
import PortSightKit

/// News about the holdings: the relay's GET /news once paired (RelayMarket.newsState), the built-in news before.
/// Until the Mac mini opens /news (404) the card says 「相关新闻尚未开放」 instead of items, in plain text: that is not
/// an error.
struct DesktopRelatedNewsCard: View {
    let scope: PortfolioScope
    var openArticle: (RelatedMarketNews) -> Void
    /// Pairing switches the card from the built-in news to the relay's (RelayNotices.usesRelay reads this store).
    @ObservedObject private var server = ServerStore.shared

    var body: some View {
        let state = RelayMarket.newsState(scope: scope)
        let articles = state.items
        DesktopCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                DesktopSectionTitle(title: "相关新闻")
                if articles.isEmpty {
                    DesktopMarketCardEmpty(isLoading: state.isLoading, title: state.emptyTitle ?? "暂时没有相关新闻",
                                           detail: state.emptyDetail)
                }
                ForEach(articles) { article in
                    Button { openArticle(article) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(article.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(2).multilineTextAlignment(.leading)
                            HStack(spacing: 6) {
                                Text(article.symbols.isEmpty ? "宏观" : article.symbols.sorted().joined(separator: " · "))
                                    .foregroundStyle(DesktopTheme.blue)
                                Spacer(minLength: 4)
                                Text(article.publishedAt, format: .relative(presentation: .numeric))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }.font(.system(size: 10))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("related_news_" + article.id)
                    if article.id != articles.last?.id { Divider().opacity(0.45) }
                }
                DesktopMarketCardNotes(note: state.note, savedNote: state.savedNote)
            }
        }
        .accessibilityIdentifier("related_news_card")
        // The store keeps reads at least 5 minutes apart by itself; before pairing nothing is read.
        .task {
            guard RelayNotices.usesRelay else { return }
            await RelayMarket.news.load()
        }
    }
}

/// What a calendar or news card shows instead of items: a calm line (an empty calendar, a feed not open yet), or
/// 正在读取… while the first read is under way.
struct DesktopMarketCardEmpty: View {
    let isLoading: Bool
    let title: String
    var detail: String? = nil

    var body: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在读取…").font(.callout).foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout).foregroundStyle(.secondary)
                if let detail { Text(detail).font(.caption).foregroundStyle(.tertiary) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The relay's own note under a market card (e.g. why earnings dates are missing), and "离线：显示 HH:mm 保存的…"
/// while the items are a saved copy.
struct DesktopMarketCardNotes: View {
    let note: String?
    let savedNote: String?

    var body: some View {
        if note != nil || savedNote != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let note {
                    Text(note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let savedNote {
                    Label(savedNote, systemImage: "wifi.slash").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 10))
            .padding(.top, 2)
        }
    }
}
