//
//  MarketContextSection.swift
//  PortSight
//
//  资产 · 概览 market context, below the home cards (matches the Mac 概览 market context): 相关新闻,
//  下一件重大事件 with a live countdown, and the 市场热力图 (US-stock heatmap). Everything follows the 全部 / 个人 / 量化 scope.
//  Once a relay is paired, news and the calendar come from the Mac mini (GET /news, GET /calendar, RelayMarket), with
//  the built-in news and events in their place while the relay has none.
//

import SwiftUI
import SwiftData
import PortSightKit

struct MarketContextSection: View {
    @EnvironmentObject private var demo: PortfolioDemo
    /// RelayMarket switches to the relay's feeds with the pairing.
    @ObservedObject private var server = ServerStore.shared
    @State private var openArticle: RelatedMarketNews?

    var body: some View {
        VStack(spacing: 14) {
            RelatedNewsCard(state: RelayMarket.newsState(scope: demo.scope)) { openArticle = $0 }
            UpcomingEventCard(scope: demo.scope)
            // The built-in heatmap, paired or not (the relay has no market prices yet).
            SectorFlowCard()
        }
        .padding(.top, 14)
        .animation(.smooth, value: demo.scope)
        // Both stores read at most every 5 minutes by themselves; nothing to read before pairing.
        .task(id: server.pairingState) {
            guard RelayNotices.usesRelay else { return }
            await RelayMarket.calendar.load()
            await RelayMarket.news.load()
        }
        .sheet(item: $openArticle) { article in
            NavigationStack { NewsDetailView(article: article) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - 相关新闻

private struct RelatedNewsCard: View {
    let state: RelayMarket.CardState<RelatedMarketNews>
    var open: (RelatedMarketNews) -> Void

    private var articles: [RelatedMarketNews] { state.items }

    var body: some View {
        DemoCard(title: "相关新闻", icon: "newspaper") {
            if articles.isEmpty {
                // Not open yet, nothing found, or still reading: a plain line, not an error.
                MarketCardEmpty(title: state.emptyTitle ?? "暂无相关新闻", detail: state.emptyDetail,
                                isLoading: state.isLoading)
            }
            ForEach(articles) { article in
                Button { open(article) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(article.title).font(.subheadline.weight(.medium))
                            .lineLimit(2).multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text(article.symbols.isEmpty ? "宏观" : article.symbols.sorted().joined(separator: " · "))
                                .foregroundStyle(.blue)
                            Spacer(minLength: 4)
                            Text(article.publishedAt, format: .relative(presentation: .numeric))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("related_news_" + article.id)
                if article.id != articles.last?.id { Divider() }
            }
            MarketCardNotes(note: state.note, savedNote: state.savedNote)
        }
    }
}

/// What a market card shows instead of its items.
private struct MarketCardEmpty: View {
    let title: String
    var detail: String?
    var isLoading = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if isLoading { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                if let detail { Text(detail).font(.caption).foregroundStyle(.tertiary) }
            }
        }
    }
}

/// The relay's own note (e.g. why there are no earnings dates yet) and the offline line, under a card's items.
private struct MarketCardNotes: View {
    let note: String?
    let savedNote: String?

    var body: some View {
        if let note {
            Text(note).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let savedNote {
            Label(savedNote, systemImage: "icloud.slash").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct NewsDetailView: View {
    let article: RelatedMarketNews
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(article.title).font(.title2.weight(.semibold))
                HStack {
                    Label("快讯", systemImage: "newspaper")
                    Spacer()
                    Text(article.publishedAt, format: .dateTime.month().day().hour().minute())
                }
                .font(.caption).foregroundStyle(.secondary)
                Text(article.summary).font(.body).lineSpacing(5)
                if !article.symbols.isEmpty {
                    Text("相关资产 · " + article.symbols.sorted().joined(separator: " / "))
                        .font(.callout).foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("新闻")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .close) { dismiss() }
            }
        }
    }
}

// MARK: - 下一件重大事件

private struct UpcomingEventCard: View {
    let scope: PortfolioScope
    /// The built-in calendar until a relay is paired, the relay's after.
    @ObservedObject private var server = ServerStore.shared

    var body: some View {
        DemoCard(title: "下一件重大事件", icon: "calendar") {
            // Only this card updates each second.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let event = RelayMarket.nextEvent(scope: scope, after: context.date) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(event.title).font(.subheadline.weight(.medium))
                            Spacer(minLength: 4)
                            Text(event.category).font(.caption).foregroundStyle(.secondary)
                        }
                        countdown(event: event, now: context.date)
                        Text(event.date, format: .dateTime.month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    // The relay's empty 14 days are normal (「未来 14 天没有重要事件」), not an error.
                    let state = RelayMarket.calendarState(scope: scope, now: context.date)
                    MarketCardEmpty(title: state.emptyTitle ?? "暂无后续事件", detail: state.emptyDetail,
                                    isLoading: state.isLoading)
                }
            }
            let state = RelayMarket.calendarState(scope: scope)
            MarketCardNotes(note: state.note, savedNote: state.savedNote)
        }
        .accessibilityIdentifier("upcoming_event_card")
    }

    private func countdown(event: MarketCalendarEvent, now: Date) -> some View {
        let time = EventCountdown(deadline: event.date, now: now)
        let values = [time.days, time.hours, time.minutes, time.seconds]
        let units = ["天", "时", "分", "秒"]
        return HStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(values[index], format: .number.precision(.integerLength(2...)))
                        .font(.title2.weight(.semibold)).fontDesign(.rounded).monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    Text(units[index]).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .animation(.smooth, value: time.seconds)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("距\(event.title)还有 \(time.days) 天 \(time.hours) 小时 \(time.minutes) 分 \(time.seconds) 秒")
    }
}

// MARK: - 市场热力图

/// US-stock heatmap (replaces 板块资金流向): sectors as labelled groups, each stock a tile sized by market
/// cap and coloured by the day change or net money flow. Tap a tile for its figures; tap a sector name, or
/// pick it from the 板块 menu (which also reaches sectors too small for a name), to zoom.
private struct SectorFlowCard: View {
    let sectors: [HeatmapSector]
    @State private var metric: HeatmapColorMetric = .change
    @State private var zoomedID: String?
    @State private var openStock: HeatmapStock?

    init(sectors: [HeatmapSector] = DemoMarketHeatmap.sectors) {
        self.sectors = sectors
    }

    private var zoomed: HeatmapSector? { sectors.first { $0.id == zoomedID } }
    private var shown: [HeatmapSector] { zoomed.map { [$0] } ?? sectors }

    var body: some View {
        DemoCard(title: zoomed?.name ?? "市场热力图", icon: "square.grid.2x2") {
            HStack(spacing: 8) {
                if zoomed != nil {
                    Button { zoomedID = nil } label: {
                        // Same 30pt label height as the 板块 menu beside it, so both glass buttons line up.
                        Label("全部", systemImage: "chevron.left")
                            .frame(height: 30)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .accessibilityIdentifier("heatmap_back")
                }
                sectorMenu
                Picker("颜色", selection: $metric) {
                    ForEach(HeatmapColorMetric.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("heatmap_metric")
            }
            Text(subtitle)
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .contentTransition(.numericText())
            map.frame(height: 320)
            legend
        }
        .animation(.smooth(duration: 0.35), value: zoomedID)
        .animation(.smooth, value: metric)
        .sensoryFeedback(.selection, trigger: zoomedID)
        .sheet(item: $openStock) { stock in
            let sector = sectors.first { $0.stocks.contains(stock) }
            HeatmapStockSheet(stock: stock, sector: sector, zoom: zoomAction(for: sector))
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .accessibilityIdentifier("market_heatmap_card")
    }

    private func heatmapColor(_ value: Double, scale: HeatmapColorScale) -> Color {
        let intensity = scale.intensity(value)
        guard abs(intensity) > 0.02 else { return Color(red: 0.43, green: 0.48, blue: 0.54) }
        // Keep small moves saturated; vary brightness rather than mixing the tile with grey.
        return Color(hue: intensity > 0 ? 0.40 : 0.005,
                     saturation: 0.76 + 0.18 * abs(intensity),
                     brightness: 0.82 - 0.20 * abs(intensity))
    }

    private var subtitle: String {
        if let zoomed {
            return "\(zoomed.mappedStocks.count) 只 · " + HeatmapFormat.change(zoomed.change) + " · 净流入 " + HeatmapFormat.netFlow(zoomed.netFlow)
        }
        return "美股 · 面积为市值 · 颜色为" + metric.title
    }

    /// Every sector, including ones too small for a header, can be zoomed from here.
    private var sectorMenu: some View {
        Menu {
            Button("全部板块", systemImage: "square.grid.2x2") { zoomedID = nil }
                .disabled(zoomedID == nil)
            Divider()
            Picker("板块", selection: $zoomedID) {
                ForEach(sectors) { sector in
                    Text(sector.name + "  " + HeatmapFormat.change(sector.change)).tag(Optional(sector.id))
                }
            }
        } label: {
            Label("板块", systemImage: "line.3.horizontal.decrease")
                .labelStyle(.iconOnly)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .accessibilityLabel("选择板块")
        .accessibilityIdentifier("heatmap_sector_menu")
    }

    private var map: some View {
        GeometryReader { geometry in
            let layout = HeatmapLayout(sectors: shown, in: CGRect(origin: .zero, size: geometry.size),
                                       headerHeight: 16, sectorGap: 3)
            ZStack(alignment: .topLeading) {
                ForEach(layout.tiles) { tile in
                    let sector = shown.first { $0.id == tile.sectorID }
                    Button { openStock = tile.stock } label: {
                        HeatmapTile(stock: tile.stock, sectorName: sector?.name, size: tile.frame.size, metric: metric,
                                    color: heatmapColor(metric.value(of: tile.stock), scale: metric.scale))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAction(named: zoomedID == nil ? "放大\(sector?.name ?? "板块")" : "返回全部板块") {
                        zoomedID = zoomedID == nil ? tile.sectorID : nil
                    }
                    .frame(width: max(0, tile.frame.width - 1), height: max(0, tile.frame.height - 1))
                    .position(x: tile.frame.midX, y: tile.frame.midY)
                    .transition(.opacity)
                }
                ForEach(layout.sectors) { frame in
                    if let header = frame.header {
                        Button { zoomedID = zoomedID == frame.id ? nil : frame.id } label: {
                            HStack(spacing: 2) {
                                Text(frame.sector.name).lineLimit(1)
                                Image(systemName: zoomedID == frame.id ? "chevron.left" : "chevron.right")
                                    .font(.system(size: 7, weight: .bold))
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: header.width, height: header.height)
                        .position(x: header.midX, y: header.midY)
                        .accessibilityLabel(frame.sector.name)
                        .accessibilityHint(zoomedID == frame.id ? "返回全部板块" : "放大这个板块")
                        .accessibilityIdentifier("heatmap_sector_" + frame.id)
                        .transition(.opacity)
                    } else if frame.showsCompactLabel {
                        // Headerless sector: a small name chip that zooms like a header.
                        Button { zoomedID = zoomedID == frame.id ? nil : frame.id } label: {
                            Text(frame.sector.name)
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3).padding(.vertical, 1)
                                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .accessibilityLabel(frame.sector.name)
                        .accessibilityHint("放大这个板块")
                        .accessibilityIdentifier("heatmap_sector_" + frame.id)
                        .padding(3)
                        .frame(width: frame.body.width, height: frame.body.height, alignment: .topLeading)
                        .position(x: frame.body.midX, y: frame.body.midY)
                        .transition(.opacity)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var legend: some View {
        let labels = metric.legendLabels
        let scale = metric.scale
        let steps = [-1.0, -0.66, -0.33, 0, 0.33, 0.66, 1]
        return HStack(spacing: 6) {
            Text(labels.low)
            HStack(spacing: 1) {
                ForEach(steps, id: \.self) { step in
                    heatmapColor(step * scale.limit, scale: scale).frame(height: 6)
                }
            }
            .frame(maxWidth: 140)
            .clipShape(Capsule())
            Text(labels.high)
            Spacer(minLength: 4)
            Text(zoomed == nil ? "点板块名放大" : "点股票看详情")
        }
        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
    }

    /// The sheet's 只看 action; nil when the map is already zoomed to that sector.
    private func zoomAction(for sector: HeatmapSector?) -> (() -> Void)? {
        guard let sector, zoomedID != sector.id else { return nil }
        return { zoomedID = sector.id }
    }
}

/// One tile: logo, ticker and figure when large; ticker only when mid-size; logo only when small; colour only when tiny.
private struct HeatmapTile: View {
    let stock: HeatmapStock
    let sectorName: String?
    let size: CGSize
    let metric: HeatmapColorMetric
    let color: Color

    var body: some View {
        let side = min(size.width, size.height)
        ZStack {
            Rectangle().fill(color)
            switch HeatmapLayout.detail(for: CGRect(origin: .zero, size: size)) {
            case .full:
                let font = min(20, max(9, min(size.width / 4.6, size.height / 4)))
                VStack(spacing: 2) {
                    if size.height >= 62 { HeatmapLogo(symbol: stock.symbol, size: min(28, max(14, side * 0.26))) }
                    Text(stock.symbol)
                        .font(.system(size: font, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if HeatmapLayout.showsValue(for: CGRect(origin: .zero, size: size)) {
                        Text(value)
                            .font(.system(size: max(8, font * 0.64), weight: .medium))
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .contentTransition(.numericText(value: metric.value(of: stock)))
                    }
                }
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(2)
            case .logo:
                HeatmapLogo(symbol: stock.symbol, size: min(20, side * 0.62))
            case .color:
                EmptyView()
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stock.name) \(stock.symbol)" + (sectorName.map { "，" + $0 } ?? ""))
        .accessibilityValue(HeatmapFormat.change(stock.change) + "，资金净流入 " + HeatmapFormat.netFlow(stock.netFlow))
        .accessibilityIdentifier("heatmap_tile_" + stock.symbol)
    }

    private var value: String {
        switch metric {
        case .change: HeatmapFormat.change(stock.change)
        case .netFlow: HeatmapFormat.compactNetFlow(stock.netFlow)
        }
    }
}

/// The stock's real icon (SymbolLogoStore, downloaded once and kept), or the letter placeholder until it is here.
private struct HeatmapLogo: View {
    let symbol: String
    let size: CGFloat

    var body: some View {
        SymbolLogoView(symbol: symbol, crypto: false, size: size)
    }
}

/// Small sheet for a tapped tile.
private struct HeatmapStockSheet: View {
    let stock: HeatmapStock
    let sector: HeatmapSector?
    /// Zooms the map to this stock's sector; nil when it is already zoomed there.
    var zoom: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    HeatmapLogo(symbol: stock.symbol, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stock.name).font(.headline)
                        Text(stock.symbol + (sector.map { " · " + $0.name } ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(stock.price, format: .currency(code: "USD").locale(Locale(identifier: "en_US")))
                        .font(.title2.weight(.semibold)).fontDesign(.rounded)
                    Text(HeatmapFormat.priceChange(stock.priceChange) + "  " + HeatmapFormat.change(stock.change))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(stock.change >= 0 ? .green : .red)
                }
                .monospacedDigit()
                VStack(spacing: 8) {
                    LabeledContent("市值", value: HeatmapFormat.marketCap(stock.marketCap))
                    LabeledContent("资金净流入") {
                        Text(HeatmapFormat.netFlow(stock.netFlow)).foregroundStyle(stock.netFlow >= 0 ? .green : .red)
                    }
                }
                .font(.subheadline).monospacedDigit()
                if let zoom, let sector {
                    Button {
                        zoom()
                        dismiss()
                    } label: {
                        Label("只看\(sector.name)", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .accessibilityIdentifier("heatmap_zoom_sector")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .navigationTitle(stock.symbol)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}
