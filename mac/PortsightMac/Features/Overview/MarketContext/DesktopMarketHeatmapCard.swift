import SwiftUI
import PortSightKit

/// US-stock market heatmap: sectors as labelled groups, each stock a tile sized by market cap and
/// coloured by the day change or the net money flow. Hover a tile for its figures, click a sector
/// name (or pick it from the 板块 menu, which also reaches sectors too small for a name) to zoom into it,
/// click a held stock to open its detail. Read-only, built-in figures.
struct DesktopMarketHeatmapCard: View {
    var sectors: [HeatmapSector] = DemoMarketHeatmap.sectors
    var mapHeight: CGFloat = 330

    @EnvironmentObject private var demo: PortfolioDemo
    @EnvironmentObject private var market: MarketStatusViewModel
    @State private var metric: HeatmapColorMetric = .change
    @State private var zoomedID: String?
    @State private var hoveredID: String?
    @State private var hoverPoint: CGPoint = .zero
    @State private var openAsset: PortfolioAsset?

    private var zoomed: HeatmapSector? { sectors.first { $0.id == zoomedID } }
    private var shown: [HeatmapSector] { zoomed.map { [$0] } ?? sectors }

    var body: some View {
        DesktopCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                header
                map.frame(height: mapHeight)
                legend
            }
        }
        .animation(.smooth(duration: 0.35), value: zoomedID)
        .animation(.smooth, value: metric)
        .closesForPush($openAsset)
        .sheet(item: $openAsset) { asset in
            DesktopSheetContainer(title: asset.symbol + " · " + asset.name) {
                AssetDetailView(asset: asset)
            }
            .environmentObject(demo).environmentObject(market)
        }
        .onChange(of: demo.showNotifications) { _, show in
            if show { openAsset = nil }
        }
        .accessibilityIdentifier("market_heatmap_card")
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            if zoomed != nil {
                Button { zoomedID = nil } label: {
                    Label("全部板块", systemImage: "chevron.left")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .accessibilityIdentifier("heatmap_back")
            }
            DesktopSectionTitle(title: zoomed?.name ?? "市场热力图", subtitle: subtitle)
            Spacer(minLength: 8)
            sectorMenu
            DesktopCapsulePicker(title: "颜色", options: HeatmapColorMetric.allCases, selection: $metric) { $0.title }
            .fixedSize()
            .accessibilityIdentifier("heatmap_metric")
        }
    }

    /// Every sector, including ones too small for a header, can be zoomed from here.
    private var sectorMenu: some View {
        Menu {
            Button("全部板块") { zoomedID = nil }
                .disabled(zoomedID == nil)
            Divider()
            ForEach(sectors) { sector in
                Toggle(isOn: Binding(get: { zoomedID == sector.id },
                                     set: { zoomedID = $0 ? sector.id : nil })) {
                    Text(sector.name + "  " + HeatmapFormat.change(sector.change))
                }
            }
        } label: {
            Label("板块", systemImage: "square.grid.2x2")
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .controlSize(.small)
        .fixedSize()
        .help("选择板块放大")
        .accessibilityIdentifier("heatmap_sector_menu")
    }

    private var subtitle: String {
        if let zoomed {
            return "\(zoomed.mappedStocks.count) 只 · " + HeatmapFormat.change(zoomed.change) + " · 净流入 " + HeatmapFormat.netFlow(zoomed.netFlow)
        }
        return "美股 · 面积为市值 · 颜色为" + metric.title
    }

    // MARK: Map

    private var map: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let layout = HeatmapLayout(sectors: shown, in: bounds, headerHeight: 18, sectorGap: 4)
            ZStack(alignment: .topLeading) {
                ForEach(layout.tiles) { tile in
                    let sector = shown.first { $0.id == tile.sectorID }
                    let isHeld = holding(for: tile.stock) != nil
                    DesktopHeatmapTile(stock: tile.stock, sectorName: sector?.name, size: tile.frame.size, metric: metric,
                                       color: tileColor(tile.stock), isHovered: hoveredID == tile.id, isHeld: isHeld)
                        .frame(width: max(0, tile.frame.width - 1), height: max(0, tile.frame.height - 1))
                        .position(x: tile.frame.midX, y: tile.frame.midY)
                        .onTapGesture { if isHeld { open(tile.stock) } }
                        .accessibilityAction(named: zoomedID == nil ? "放大\(sector?.name ?? "板块")" : "返回全部板块") {
                            zoomedID = zoomedID == nil ? tile.sectorID : nil
                        }
                        .transition(.opacity)
                }
                ForEach(layout.sectors) { frame in
                    if let header = frame.header {
                        sectorHeader(frame.sector, width: header.width)
                            .frame(width: header.width, height: header.height)
                            .position(x: header.midX, y: header.midY)
                            .transition(.opacity)
                    } else if frame.showsCompactLabel {
                        compactSectorLabel(frame.sector)
                            .padding(3)
                            .frame(width: frame.body.width, height: frame.body.height, alignment: .topLeading)
                            .position(x: frame.body.midX, y: frame.body.midY)
                            .transition(.opacity)
                    }
                }
                if let id = hoveredID, let tile = layout.tiles.first(where: { $0.id == id }) {
                    tooltip(tile.stock, sector: shown.first { $0.id == tile.sectorID })
                        .fixedSize()
                        .position(tooltipCenter(in: geometry.size))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hoverPoint = point
                    let id = layout.tile(at: point)?.id
                    if id != hoveredID { hoveredID = id }
                case .ended:
                    hoveredID = nil
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sectorHeader(_ sector: HeatmapSector, width: CGFloat) -> some View {
        Button { zoomedID = zoomedID == sector.id ? nil : sector.id } label: {
            HStack(spacing: 3) {
                Text(sector.name).lineLimit(1)
                Image(systemName: zoomedID == sector.id ? "chevron.left" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                Spacer(minLength: 0)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(zoomedID == sector.id ? "返回全部板块" : "只看\(sector.name)")
        .accessibilityLabel(sector.name)
        .accessibilityHint(zoomedID == sector.id ? "返回全部板块" : "放大这个板块")
        .accessibilityIdentifier("heatmap_sector_" + sector.id)
    }

    /// Name chip for a sector too small for a header strip; it zooms like a header.
    private func compactSectorLabel(_ sector: HeatmapSector) -> some View {
        Button { zoomedID = zoomedID == sector.id ? nil : sector.id } label: {
            Text(sector.name)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 3).padding(.vertical, 1)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("只看\(sector.name)")
        .accessibilityLabel(sector.name)
        .accessibilityHint("放大这个板块")
        .accessibilityIdentifier("heatmap_sector_" + sector.id)
    }

    private func heatmapColor(_ value: Double, scale: HeatmapColorScale) -> Color {
        let intensity = scale.intensity(value)
        guard abs(intensity) > 0.02 else { return Color(red: 0.43, green: 0.48, blue: 0.54) }
        return Color(hue: intensity > 0 ? 0.40 : 0.005,
                     saturation: 0.76 + 0.18 * abs(intensity),
                     brightness: 0.82 - 0.20 * abs(intensity))
    }

    private func tileColor(_ stock: HeatmapStock) -> Color {
        heatmapColor(metric.value(of: stock), scale: metric.scale)
    }

    private func holding(for stock: HeatmapStock) -> DemoHolding? {
        demo.holdings.first { $0.symbol == stock.symbol }
    }

    private func open(_ stock: HeatmapStock) {
        if let holding = holding(for: stock) { openAsset = holding.asset }
    }

    // MARK: Tooltip

    private static let tooltipSize = CGSize(width: 230, height: 150)

    private func tooltipCenter(in size: CGSize) -> CGPoint {
        let w = Self.tooltipSize.width, h = Self.tooltipSize.height, gap: CGFloat = 14
        var x = hoverPoint.x + gap + w / 2
        if x + w / 2 > size.width { x = hoverPoint.x - gap - w / 2 }
        var y = hoverPoint.y + gap + h / 2
        if y + h / 2 > size.height { y = hoverPoint.y - gap - h / 2 }
        return CGPoint(x: min(max(w / 2, x), max(w / 2, size.width - w / 2)),
                       y: min(max(h / 2, y), max(h / 2, size.height - h / 2)))
    }

    private func tooltip(_ stock: HeatmapStock, sector: HeatmapSector?) -> some View {
        let tint = DesktopTheme.pnlColor(stock.change)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                DesktopSymbol(symbol: stock.symbol, crypto: false, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(stock.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(stock.symbol + (sector.map { " · " + $0.name } ?? ""))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(DesktopTheme.money(stock.price)).font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(HeatmapFormat.priceChange(stock.priceChange) + "  " + HeatmapFormat.change(stock.change))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(tint)
            }
            .monospacedDigit()
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("市值").foregroundStyle(.secondary)
                    Text(HeatmapFormat.marketCap(stock.marketCap))
                }
                GridRow {
                    Text("资金净流入").foregroundStyle(.secondary)
                    Text(HeatmapFormat.netFlow(stock.netFlow)).foregroundStyle(DesktopTheme.pnlColor(stock.netFlow))
                }
            }
            .font(.system(size: 11)).monospacedDigit()
            if holding(for: stock) != nil {
                Label("已持有 · 点击查看详情", systemImage: "briefcase").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: Self.tooltipSize.width, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DesktopTheme.border) }
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    // MARK: Legend

    private var legend: some View {
        let labels = metric.legendLabels
        let scale = metric.scale
        let steps = [-1.0, -0.66, -0.33, 0, 0.33, 0.66, 1]
        return HStack(spacing: 8) {
            Text(labels.low)
            HStack(spacing: 1) {
                ForEach(steps, id: \.self) { step in
                    heatmapColor(step * scale.limit, scale: scale).frame(width: 22, height: 8)
                }
            }
            .clipShape(Capsule())
            Text(labels.high)
            Spacer()
            Text(zoomed == nil ? "点板块名放大，点已持有的股票查看详情" : "点已持有的股票查看详情")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
}

/// One tile. Large tiles show logo, ticker and the figure; mid-size ones the ticker only; small ones only
/// the logo; tiny ones only colour. Only held stocks open something, so only they carry the button trait.
private struct DesktopHeatmapTile: View {
    let stock: HeatmapStock
    let sectorName: String?
    let size: CGSize
    let metric: HeatmapColorMetric
    let color: Color
    let isHovered: Bool
    let isHeld: Bool

    var body: some View {
        let detail = HeatmapLayout.detail(for: CGRect(origin: .zero, size: size))
        let side = min(size.width, size.height)
        ZStack {
            Rectangle().fill(color)
            switch detail {
            case .full:
                let font = min(24, max(10, min(size.width / 4.6, size.height / 4)))
                VStack(spacing: max(2, font * 0.18)) {
                    if size.height >= 64, hasMark { logo(min(34, max(14, side * 0.26))) }
                    Text(stock.symbol)
                        .font(.system(size: font, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if HeatmapLayout.showsValue(for: CGRect(origin: .zero, size: size)) {
                        Text(value)
                            .font(.system(size: max(9, font * 0.62), weight: .medium))
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .contentTransition(.numericText(value: metric.value(of: stock)))
                    }
                }
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(3)
            case .logo:
                if hasMark {
                    logo(min(22, side * 0.62))
                } else {
                    // No real mark for this company: a tiny ticker reads better than a lettered placeholder.
                    Text(stock.symbol)
                        .font(.system(size: max(7, min(11, size.width / 4.2)), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .padding(1)
                }
            case .color:
                EmptyView()
            }
        }
        .overlay {
            if isHovered { Rectangle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stock.name) \(stock.symbol)" + (sectorName.map { "，" + $0 } ?? ""))
        .accessibilityValue(HeatmapFormat.change(stock.change) + "，资金净流入 " + HeatmapFormat.netFlow(stock.netFlow))
        .accessibilityAddTraits(isHeld ? .isButton : [])
        .accessibilityHint(isHeld ? "已持有，查看详情" : "")
        .accessibilityIdentifier("heatmap_tile_" + stock.symbol)
        .task(id: stock.symbol) { await SymbolLogoStore.shared.load(stock.symbol, crypto: false) }
    }

    private var value: String {
        switch metric {
        case .change: HeatmapFormat.change(stock.change)
        case .netFlow: HeatmapFormat.compactNetFlow(stock.netFlow)
        }
    }

    /// Only symbols whose real icon is on this device (SymbolLogoStore) get a logo; the others would show a single
    /// letter, so they keep the ticker. The tile itself asks for the icon (see `body`).
    private var hasMark: Bool { SymbolLogoStore.shared.image(stock.symbol, crypto: false) != nil }

    private func logo(_ size: CGFloat) -> some View {
        DesktopSymbol(symbol: stock.symbol, crypto: false, size: size)
            .background(.white, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .environment(\.colorScheme, .light)
    }
}

#Preview {
    DesktopMarketHeatmapCard()
        .environmentObject(PortfolioDemo())
        .environmentObject(MarketStatusViewModel())
        .frame(width: 820)
        .padding()
}
