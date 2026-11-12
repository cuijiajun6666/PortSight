import CoreGraphics
import Foundation
import SwiftUI

// MARK: - Model

/// One stock tile of the market heatmap.
public struct HeatmapStock: Identifiable, Hashable, Sendable {
    public var id: String { symbol }
    public let symbol: String
    public let name: String
    /// Market capitalisation in USD billions; drives the tile area.
    public let marketCap: Double
    /// Last price in USD.
    public let price: Double
    /// Day change as a fraction (0.012 = +1.2%).
    public let change: Double
    /// Net money flow today in USD millions; negative is an outflow.
    public let netFlow: Double

    public init(symbol: String, name: String, marketCap: Double, price: Double, change: Double, netFlow: Double) {
        self.symbol = symbol
        self.name = name
        self.marketCap = marketCap
        self.price = price
        self.change = change
        self.netFlow = netFlow
    }

    /// Absolute price change since the previous close.
    public var priceChange: Double { price - price / (1 + change) }

    /// Whether the stock gets a tile: only finite, positive market caps have an area (see `Treemap.squarify`).
    public var hasArea: Bool { marketCap.isFinite && marketCap > 0 }
}

/// A labelled group of stocks (a sector) in the heatmap.
public struct HeatmapSector: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let stocks: [HeatmapStock]

    public init(id: String, name: String, stocks: [HeatmapStock]) {
        self.id = id
        self.name = name
        self.stocks = stocks
    }

    /// The stocks that get a tile. Zero, negative and non-finite caps are left out of every sector figure,
    /// so a sector's area, change and flow always match the tiles it shows.
    public var mappedStocks: [HeatmapStock] { stocks.filter(\.hasArea) }

    public var marketCap: Double { mappedStocks.reduce(0) { $0 + $1.marketCap } }
    public var netFlow: Double { mappedStocks.reduce(0) { $0 + ($1.netFlow.isFinite ? $1.netFlow : 0) } }
    /// Market-cap-weighted day change (stocks with a non-finite change are skipped).
    public var change: Double {
        let weighted = mappedStocks.filter(\.change.isFinite)
        let cap = weighted.reduce(0) { $0 + $1.marketCap }
        return cap > 0 ? weighted.reduce(0) { $0 + $1.change * $1.marketCap } / cap : 0
    }
}

/// What the tile colour shows.
public enum HeatmapColorMetric: String, CaseIterable, Identifiable, Sendable {
    case change, netFlow
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .change: "涨跌幅"
        case .netFlow: "资金净流入"
        }
    }

    public func value(of stock: HeatmapStock) -> Double {
        self == .change ? stock.change : stock.netFlow
    }

    public func value(of sector: HeatmapSector) -> Double {
        self == .change ? sector.change : sector.netFlow
    }

    /// Default colour scale: ±3% for change, ±500M USD for a single stock's net flow.
    public var scale: HeatmapColorScale {
        switch self {
        case .change: HeatmapColorScale(limit: 0.03)
        case .netFlow: HeatmapColorScale(limit: 500)
        }
    }

    /// Legend labels for the two ends of the scale.
    public var legendLabels: (low: String, high: String) {
        switch self {
        case .change: ("−3%", "+3%")
        case .netFlow: ("流出 5 亿", "流入 5 亿")
        }
    }
}

// MARK: - Colour

/// Diverging colour scale: neutral grey at zero, toward the loss colour below and the profit colour above.
/// Values beyond `limit` are clamped, so a ±3% day and a ±8% day share the deepest shade.
public struct HeatmapColorScale: Sendable {
    public let limit: Double

    public init(limit: Double = 0.03) {
        self.limit = max(.ulpOfOne, abs(limit))
    }

    /// Signed intensity in -1...1.
    public func intensity(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(-1, value / limit))
    }

    /// Tile colour. Apps pass their own profit / loss colours.
    public func color(_ value: Double, up: Color, down: Color,
                      neutral: Color = Color(red: 0.42, green: 0.44, blue: 0.47)) -> Color {
        let t = intensity(value)
        guard abs(t) > 0.02 else { return neutral }
        // Even a small move is clearly tinted; bigger moves get deeper and darker.
        let tint = (t > 0 ? up : down).mix(with: .black, by: 0.42 * abs(t))
        return neutral.mix(with: tint, by: 0.35 + 0.65 * abs(t))
    }
}

// MARK: - Layout

/// Frames for a nested heatmap: sectors, each with an optional header strip, then stock tiles inside.
public struct HeatmapLayout: Sendable {
    public struct SectorFrame: Identifiable, Sendable {
        public var id: String { sector.id }
        public let sector: HeatmapSector
        /// The sector's full rectangle (header plus body).
        public let frame: CGRect
        /// Header strip for the sector name; nil when the sector is too small to label.
        public let header: CGRect?
        /// Area the stock tiles fill.
        public let body: CGRect

        /// A headerless sector that still has room for a small name chip in its top-left corner.
        public var showsCompactLabel: Bool { header == nil && body.width >= 36 && body.height >= 22 }
    }

    public struct TileFrame: Identifiable, Sendable {
        public var id: String { stock.id }
        public let stock: HeatmapStock
        public let sectorID: String
        public let frame: CGRect
    }

    public let sectors: [SectorFrame]
    public let tiles: [TileFrame]

    /// Builds the nested layout: sectors sized by total market cap, then stocks by market cap inside each sector.
    /// - Parameters:
    ///   - headerHeight: height of each sector's label strip.
    ///   - sectorGap: space between sectors.
    public init(sectors: [HeatmapSector], in rect: CGRect, headerHeight: CGFloat = 18, sectorGap: CGFloat = 3) {
        let sectorRects = Treemap.squarify(sectors.map(\.marketCap), in: rect)
        var sectorFrames: [SectorFrame] = []
        var tiles: [TileFrame] = []
        for (sector, outer) in zip(sectors, sectorRects) where outer.width > 0 && outer.height > 0 {
            // Half the gap on every inner edge; outer edges stay flush with `rect`.
            let inner = CGRect(
                x: outer.minX + (outer.minX > rect.minX + 0.5 ? sectorGap / 2 : 0),
                y: outer.minY + (outer.minY > rect.minY + 0.5 ? sectorGap / 2 : 0),
                width: outer.width - (outer.minX > rect.minX + 0.5 ? sectorGap / 2 : 0) - (outer.maxX < rect.maxX - 0.5 ? sectorGap / 2 : 0),
                height: outer.height - (outer.minY > rect.minY + 0.5 ? sectorGap / 2 : 0) - (outer.maxY < rect.maxY - 0.5 ? sectorGap / 2 : 0)
            )
            guard inner.width > 0, inner.height > 0 else { continue }
            let showsHeader = inner.height >= headerHeight * 2.4 && inner.width >= 44
            let header = showsHeader ? CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: headerHeight) : nil
            let body = showsHeader
                ? CGRect(x: inner.minX, y: inner.minY + headerHeight, width: inner.width, height: inner.height - headerHeight)
                : inner
            sectorFrames.append(SectorFrame(sector: sector, frame: inner, header: header, body: body))
            // squarify gives non-positive / non-finite caps .zero rects; they are skipped below.
            let stockRects = Treemap.squarify(sector.stocks.map(\.marketCap), in: body)
            for (stock, frame) in zip(sector.stocks, stockRects) where frame.width > 0 && frame.height > 0 {
                tiles.append(TileFrame(stock: stock, sectorID: sector.id, frame: frame))
            }
        }
        self.sectors = sectorFrames
        self.tiles = tiles
    }

    /// The tile under `point`, if any.
    public func tile(at point: CGPoint) -> TileFrame? {
        tiles.first { $0.frame.contains(point) }
    }

    /// How much a tile can show at its size.
    public enum TileDetail: Sendable { case full, logo, color }

    public static func detail(for frame: CGRect) -> TileDetail {
        if frame.width >= 52 && frame.height >= 46 { return .full }
        if frame.width >= 20 && frame.height >= 20 { return .logo }
        return .color
    }

    /// Whether a `.full` tile also has room for its figure under the ticker; smaller tiles show the ticker only.
    public static func showsValue(for frame: CGRect) -> Bool {
        frame.width >= 58 && frame.height >= 52
    }
}

// MARK: - Formatting

public enum HeatmapFormat {
    /// "+1.24%" / "−0.80%".
    public static func change(_ fraction: Double) -> String {
        (fraction >= 0 ? "+" : "−") + String(format: "%.2f%%", abs(fraction) * 100)
    }

    /// "+2.95" / "−1.10" (USD).
    public static func priceChange(_ value: Double) -> String {
        (value >= 0 ? "+" : "−") + String(format: "%.2f", abs(value))
    }

    /// Market cap from USD billions: "4.40 万亿美元" or "2,600 亿美元".
    public static func marketCap(_ billions: Double) -> String {
        if billions >= 1_000 { return String(format: "%.2f 万亿美元", billions / 1_000) }
        return (billions * 10).formatted(.number.precision(.fractionLength(0))) + " 亿美元"
    }

    /// Net flow from USD millions: "+12.40 亿美元" / "−3,500 万美元"; "0 万美元" (no sign) when flat.
    public static func netFlow(_ millions: Double) -> String {
        guard millions.isFinite else { return "—" }
        let wan = (abs(millions) * 100).rounded()
        if wan == 0 { return "0 万美元" }
        let sign = millions > 0 ? "+" : "−"
        if abs(millions) >= 100 { return sign + String(format: "%.2f 亿美元", abs(millions) / 100) }
        return sign + wan.formatted(.number.precision(.fractionLength(0))) + " 万美元"
    }

    /// Short net-flow label for a tile, from USD millions: "+12.4亿" at 1 亿 and above, otherwise "−350万";
    /// "0万" (no sign) when flat. Small flows never collapse to a signed "0.0亿".
    public static func compactNetFlow(_ millions: Double) -> String {
        guard millions.isFinite else { return "—" }
        let wan = (abs(millions) * 100).rounded()
        if wan == 0 { return "0万" }
        let sign = millions > 0 ? "+" : "−"
        if wan >= 10_000 { return sign + String(format: "%.1f亿", abs(millions) / 100) }
        return sign + String(format: "%.0f万", wan)
    }
}
