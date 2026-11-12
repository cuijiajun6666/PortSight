import SwiftUI
import PortSightKit

struct DesktopNewsDetail: View {
    let article: RelatedMarketNews

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(article.title).font(.title2.weight(.semibold))
                HStack {
                    Label("快讯", systemImage: "newspaper").foregroundStyle(.secondary)
                    Spacer()
                    Text(article.publishedAt, format: .dateTime.month().day().hour().minute())
                        .foregroundStyle(.secondary)
                }.font(.caption)
                Text(article.summary).font(.body).lineSpacing(5)
                if !article.symbols.isEmpty {
                    Text("相关资产 · " + article.symbols.sorted().joined(separator: " / "))
                        .font(.callout).foregroundStyle(DesktopTheme.blue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }
}
