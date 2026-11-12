//
//  PositionsView.swift
//  PortSight
//
//  Created by Chris Cui on 28/4/2026.
//
import SwiftUI
import SwiftData
import PortSightKit

struct PositionsView: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @StateObject private var assetVM = AssetViewModel()
    @StateObject private var positionsVM = PositionsViewModel()
    @StateObject private var quoteVM = QuoteViewModel()
    @StateObject private var marketVM = MarketStatusViewModel()
    @StateObject private var pricesVM = PricesViewModel()

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StockLogoRecord.ticker) private var stockLogoRecords: [StockLogoRecord]

    @State private var allocationFilter: AllocationFilter = .all
    @State private var hasStartedInitialLoad = false
    @State private var cachedIntradayPricesBySymbol: [String: [Double]] = [:]
    @State private var intradayRefreshTask: Task<Void, Never>?
    @State private var quoteRefreshTask: Task<Void, Never>?
    @State private var searchText = ""
    @State private var sortOrder: PositionSort = .value

    private enum PositionSort: String, CaseIterable, Identifiable {
        case value = "市值"
        case pnl = "收益"
        case name = "名称"

        var id: String { rawValue }
    }

    private enum AllocationFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case stock = "股票"
        case etf = "ETF"
        case crypto = "加密货币"

        var id: String { rawValue }
    }

    private var mockCryptoHoldings: [MockCryptoHolding] {
        demo.holdings.filter { $0.kind == "加密货币" }.map { .init(symbol: $0.symbol, quantity: $0.quantity, avgCost: $0.cost) }
    }

    private var hasEtfPositions: Bool {
        positionsVM.positions.contains { $0.isEtf }
    }

    private var availableAllocationFilters: [AllocationFilter] {
        if hasEtfPositions || allocationFilter == .etf {
            return [.all, .stock, .etf, .crypto]
        }

        return [.all, .stock, .crypto]
    }

    private var allocationPickerWidth: CGFloat {
        hasEtfPositions ? 260 : 190
    }

    private var stockValue: Double {
        positionsVM.positions.map(\.marketValue).reduce(0, +)
    }

    private var nonEtfStockValue: Double {
        positionsVM.positions
            .filter { !$0.isEtf }
            .map(\.marketValue)
            .reduce(0, +)
    }

    private var etfValue: Double {
        positionsVM.positions
            .filter { $0.isEtf }
            .map(\.marketValue)
            .reduce(0, +)
    }

    private var displayedHoldingValue: Double {
        switch allocationFilter {
        case .all:
            return assetVM.totalAsset
        case .stock:
            return nonEtfStockValue
        case .etf:
            return etfValue
        case .crypto:
            return demo.crypto.reduce(0) { $0 + $1.marketValue }
        }
    }

    private var cashValue: Double {
        demo.cash
    }

    private var cryptoAssets: [PortfolioAsset] {
        if DemoPortfolioData.enabled { return demo.crypto }
        return mockCryptoHoldings.map { holding in
            let price = pricesVM.price(for: holding.instId) ?? holding.avgCost

            return PortfolioAsset(
                type: .crypto,
                symbol: holding.symbol,
                name: holding.symbol,
                quantity: holding.quantity,
                avgCost: holding.avgCost,
                currentPrice: price,
                prevClosePrice: price,
                marketValue: price * holding.quantity,
                realizedPnL: 0,
                unrealizedPnL: (price - holding.avgCost) * holding.quantity,
                pnlRatio: holding.avgCost > 0 ? (price - holding.avgCost) / holding.avgCost : 0,
                currency: "USD",
                source: "mock"
            )
        }
    }

    private var allAssets: [PortfolioAsset] {
        positionsVM.positions.map { $0.asPortfolioAsset } + cryptoAssets
    }

    /// Real positions can be short (negative market value): once paired the bar shows what is held long.
    private var weightBarItems: [AllocationItem] {
        demo.isLive ? allocationItems.filter { $0.value > 0 } : allocationItems
    }

    private var allocationItems: [AllocationItem] {
        switch allocationFilter {
        case .all:
            let cryptoCategoryValue = cryptoAssets
                .map(\.marketValue)
                .reduce(0, +)

            var result: [AllocationItem] = []

            if nonEtfStockValue > 0 {
                result.append(.init(name: "股票", value: nonEtfStockValue))
            }

            if cashValue > 0 {
                result.append(.init(name: "Cash", value: cashValue))
            }

            if etfValue > 0 {
                result.append(.init(name: "ETF", value: etfValue))
            }

            if cryptoCategoryValue > 0 {
                result.append(.init(name: "加密货币", value: cryptoCategoryValue))
            }

            return result.sorted { $0.value > $1.value }

        case .stock:
            return positionsVM.positions
                .filter { !$0.isEtf }
                .map { AllocationItem(name: $0.displaySymbol, value: $0.marketValue) }
                .sorted { $0.value > $1.value }

        case .etf:
            return positionsVM.positions
                .filter { $0.isEtf }
                .map { AllocationItem(name: $0.displaySymbol, value: $0.marketValue) }
                .sorted { $0.value > $1.value }

        case .crypto:
            return cryptoAssets
                .map { AllocationItem(name: $0.symbol, value: $0.marketValue) }
                .sorted { $0.value > $1.value }
        }
    }

    private var visibleStockPositions: [Position] {
        switch allocationFilter {
        case .all:
            return positionsVM.positions
        case .stock:
            return positionsVM.positions.filter { !$0.isEtf }
        case .etf:
            return positionsVM.positions.filter { $0.isEtf }
        case .crypto:
            return []
        }
    }

    private func matchesSearch(_ symbol: String, _ name: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || (symbol + " " + name).localizedCaseInsensitiveContains(query)
    }

    /// The rows shown in the list: the type filter, then the search text and the sort order.
    private var listedStockPositions: [Position] {
        visibleStockPositions
            .filter { matchesSearch($0.displaySymbol, $0.name) }
            .sorted {
                switch sortOrder {
                case .value: $0.marketValue > $1.marketValue
                case .pnl: $0.pnl > $1.pnl
                case .name: $0.displaySymbol < $1.displaySymbol
                }
            }
    }

    private var listedCryptoHoldings: [MockCryptoHolding] {
        func price(_ holding: MockCryptoHolding) -> Double { pricesVM.price(for: holding.instId) ?? holding.avgCost }
        return mockCryptoHoldings
            .filter { matchesSearch($0.symbol, $0.symbol) }
            .sorted {
                switch sortOrder {
                case .value: price($0) * $0.quantity > price($1) * $1.quantity
                case .pnl: (price($0) - $0.avgCost) * $0.quantity > (price($1) - $1.avgCost) * $1.quantity
                case .name: $0.symbol < $1.symbol
                }
            }
    }

    private var showsNoMatches: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
            && (allocationFilter == .crypto || listedStockPositions.isEmpty)
            && (!showsCryptoHoldings || listedCryptoHoldings.isEmpty)
    }

    private var showsCryptoHoldings: Bool {
        allocationFilter == .all || allocationFilter == .crypto
    }

    private var visibleQuoteSymbols: [String] {
        Array(visibleStockPositions.prefix(12).map(\.symbol))
    }

    private var visibleIntradaySymbols: [String] {
        Array(Set(visibleStockPositions.prefix(8).map(marketDataSymbol(for:)))).sorted()
    }

    var body: some View {
        NavigationStack {
            PortSightList {
                VStack(spacing: 12) {
                    HStack {
                        Spacer()
                        VStack {
                            Text("持仓价值")
                                .font(.system(size: 15))
                                .foregroundStyle(.gray)
                            Text("$\(displayedHoldingValue, specifier: "%.0f")")
                                .fontWeight(.bold)
                                .font(.system(size: 40))
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.25), value: displayedHoldingValue)
                            // Once paired: 「非实时 · 截至 …」 while the IBKR figures are not live.
                            if let note = demo.liveNote {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }

                    AllocationWeightBar(
                        items: weightBarItems,
                        animationKey: demo.scope.rawValue + allocationFilter.rawValue
                    )
                    // The bar keeps its last segments when given none: a fresh bar when pairing changes or the list
                    // empties, so sold segments never stay on screen.
                    .id(demo.isLive ? "live-\(weightBarItems.isEmpty)" : "builtin")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                // Tight under the search field and above the type picker; the sides keep the list's inset.
                .listRowInsets(.vertical, 2)

                Section {
                    if showsNoMatches {
                        ContentUnavailableView.search(text: searchText)
                    }
                    if allocationFilter != .crypto {
                        ForEach(listedStockPositions, id: \.symbol) { position in
                            NavigationLink {
                                AssetDetailView(asset: position.asPortfolioAsset)
                                    .environmentObject(marketVM)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HoldingRow(
                                        position: position,
                                        quote: quoteVM.quote(for: position.symbol),
                                        intradayPrices: cachedIntradayPrices(for: position)
                                    )
                                    DemoOwnershipLabel(symbol: position.displaySymbol)
                                }
                            }
                            .listRowInsets(.vertical, 6)
                        }
                    }

                    if showsCryptoHoldings {
                        ForEach(listedCryptoHoldings) { holding in
                            let price = pricesVM.price(for: holding.instId)

                            let asset = PortfolioAsset(
                                type: .crypto,
                                symbol: holding.symbol,
                                name: holding.symbol,
                                quantity: holding.quantity,
                                avgCost: holding.avgCost,
                                currentPrice: price ?? 0,
                                prevClosePrice: price ?? 0,
                                marketValue: (price ?? 0) * holding.quantity,
                                realizedPnL: 0,
                                unrealizedPnL: ((price ?? 0) - holding.avgCost) * holding.quantity,
                                pnlRatio: holding.avgCost > 0 ? ((price ?? 0) - holding.avgCost) / holding.avgCost : 0,
                                currency: "USD",
                                source: "mock"
                            )

                            NavigationLink {
                                AssetDetailView(asset: asset)
                            } label: {
                                // The same two lines as a stock row (the row, then who holds it), so both are as tall.
                                VStack(alignment: .leading, spacing: 5) {
                                    CryptoHoldingRow(
                                        holding: holding,
                                        price: price
                                    )
                                    DemoOwnershipLabel(symbol: holding.symbol)
                                }
                            }
                            .listRowInsets(.vertical, 6)
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        Picker("持仓类型", selection: Binding(
                            get: { allocationFilter },
                            set: { newValue in
                                withAnimation(.timingCurve(0.85, 0.0, 0.2, 1.0, duration: 0.85)) {
                                    allocationFilter = newValue
                                }
                            }
                        )) {
                            ForEach(availableAllocationFilters) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        Menu {
                            Picker("排序", selection: $sortOrder) {
                                ForEach(PositionSort.allCases) { Text($0.rawValue).tag($0) }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 36, height: 32)
                                .background(.quaternary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("持仓筛选与排序")
                        .accessibilityValue(sortOrder.rawValue)
                    }
                    .textCase(nil)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .contentMargins(.top, 4, for: .scrollContent)
            .portSightBackdrop()
            .searchable(text: $searchText, prompt: "搜索资产")
            .animation(.smooth, value: sortOrder)
            // Rows slide in and out as the search narrows or widens the list.
            .animation(.smooth, value: listedStockPositions.map(\.symbol) + listedCryptoHoldings.map(\.symbol))
            .toolbar {
                DemoToolbar()
            }
            .ordersDestination()
            .task {
                if DemoPortfolioData.enabled { applyDemo(); return }
                guard !hasStartedInitialLoad else { return }

                hasStartedInitialLoad = true
                loadCachedIntradayPrices()

                try? await Task.sleep(for: .milliseconds(1450))
                guard !Task.isCancelled else { return }

                assetVM.startAutoRefresh(immediately: false)
                await positionsVM.fetchPositions()
                loadCachedIntradayPrices()
                quoteVM.loadCaches(symbols: positionsVM.positions.map { $0.symbol })
                await quoteVM.refreshQuotes(symbols: visibleQuoteSymbols)
                startQuoteRefresh(initialDelay: 3)
                await syncStockLogoRecords(
                    symbols: stockLogoSymbols,
                    records: stockLogoRecords,
                    modelContext: modelContext
                )
                positionsVM.startAutoRefresh(immediately: false)
                marketVM.startPolling(every: 20)

                let cryptoInstIds = ["BTC-USDT", "ETH-USDT"]
                pricesVM.start(instIds: cryptoInstIds, every: 3)

                startIntradayRefresh(initialDelay: 3)
            }
            .onChange(of: demo.scope) { _, _ in applyDemo() }
            // Once paired: copy the IBKR figures again whenever the account is read (constant before pairing).
            .onChange(of: demo.figuresKey) { _, _ in applyDemo() }
            .onAppear {
                if DemoPortfolioData.enabled { return }
                guard hasStartedInitialLoad else { return }

                assetVM.startAutoRefresh(immediately: false)
                positionsVM.startAutoRefresh(immediately: false)
                marketVM.startPolling(every: 20)
                startIntradayRefresh(initialDelay: 2)
                startQuoteRefresh(initialDelay: 2)

                let cryptoInstIds = ["BTC-USDT", "ETH-USDT"]
                pricesVM.start(instIds: cryptoInstIds, every: 3)
            }
            .onDisappear {
                assetVM.stopAutoRefresh()
                positionsVM.stopAutoRefresh()
                marketVM.stopPolling()
                pricesVM.stop()
                stopIntradayRefresh()
                stopQuoteRefresh()
            }
            .onChange(of: hasEtfPositions) { _, hasEtfs in
                guard !hasEtfs, allocationFilter == .etf else { return }
                allocationFilter = .all
            }
            .onChange(of: stockLogoSymbols.joined(separator: "|")) { _, _ in
                if DemoPortfolioData.enabled { return }
                Task {
                    loadCachedIntradayPrices()
                    await quoteVM.refreshQuotes(
                        symbols: visibleQuoteSymbols
                    )
                    await syncStockLogoRecords(
                        symbols: stockLogoSymbols,
                        records: stockLogoRecords,
                        modelContext: modelContext
                    )
                }
            }
            .onChange(of: marketVM.session) { oldSession, newSession in
                // The session follows the clock in demo mode; the server's sparklines are not used there.
                if DemoPortfolioData.enabled { return }
                guard oldSession != .regular, newSession == .regular else { return }

                Task {
                    await refreshIntradayPrices()
                }
            }
            .environmentObject(marketVM)
        }
    }

    private func applyDemo() {
        demo.apply(to: assetVM); positionsVM.positions = demo.positions
        marketVM.applyClock()
        // The built-in crypto prices; a coin the holdings price differently (one held for real at IBKR once paired)
        // at the holding's price.
        var prices = ["BTC-USDT": 70000.0, "ETH-USDT": 3000.0]
        for coin in demo.crypto where coin.currentPrice > 0 { prices[coin.symbol + "-USDT"] = coin.currentPrice }
        pricesVM.prices = prices
        // The built-in price line of every row (the relay has no intraday prices), ending at the holding's price.
        cachedIntradayPricesBySymbol = [:]
        for position in demo.positions {
            let start = position.currentPrice * 0.98
            cachedIntradayPricesBySymbol[marketDataSymbol(for: position)] = (0..<24).map { start + Double($0) * position.currentPrice * 0.001 + sin(Double($0)) * position.currentPrice * 0.002 }
        }
    }

    private var stockLogoSymbols: [String] {
        Array(Set(positionsVM.positions.map { $0.displaySymbol.uppercased() })).sorted()
    }

    private func cachedIntradayPrices(for position: Position) -> [Double] {
        cachedIntradayPricesBySymbol[marketDataSymbol(for: position)] ?? []
    }

    private func marketDataSymbol(for position: Position) -> String {
        if position.symbol.contains(".") {
            return position.symbol
        }

        return "US.\(position.symbol)"
    }

    private func loadCachedIntradayPrices() {
        let symbols = Array(Set(positionsVM.positions.map(marketDataSymbol(for:))))
        let cachedPrices = loadCachedIntradaySparklinePrices(
            symbols: symbols,
            maximumPointCount: 48
        )

        cachedIntradayPricesBySymbol.merge(cachedPrices) { _, cached in cached }
    }

    private func startIntradayRefresh(initialDelay: Double = 0) {
        intradayRefreshTask?.cancel()
        intradayRefreshTask = Task {
            if initialDelay > 0 {
                try? await Task.sleep(
                    nanoseconds: UInt64(initialDelay * 1_000_000_000)
                )
            }

            while !Task.isCancelled {
                await refreshIntradayPrices()

                try? await Task.sleep(
                    nanoseconds: UInt64(60 * 1_000_000_000)
                )
            }
        }
    }

    private func stopIntradayRefresh() {
        intradayRefreshTask?.cancel()
        intradayRefreshTask = nil
    }

    private func startQuoteRefresh(initialDelay: Double = 0) {
        quoteRefreshTask?.cancel()
        quoteRefreshTask = Task {
            if initialDelay > 0 {
                try? await Task.sleep(
                    nanoseconds: UInt64(initialDelay * 1_000_000_000)
                )
            }

            while !Task.isCancelled {
                if marketVM.session != .closed && marketVM.session != .unknown {
                    await quoteVM.refreshQuotes(
                        symbols: visibleQuoteSymbols
                    )
                }

                try? await Task.sleep(
                    nanoseconds: UInt64(marketVM.refreshInterval * 1_000_000_000)
                )
            }
        }
    }

    private func stopQuoteRefresh() {
        quoteRefreshTask?.cancel()
        quoteRefreshTask = nil
    }

    private func refreshIntradayPrices() async {
        let symbols = visibleIntradaySymbols
        guard !symbols.isEmpty else { return }

        let prices = await fetchIntradaySparklinePrices(
            symbols: symbols,
            maximumPointCount: 48
        )

        guard !prices.isEmpty else { return }
        cachedIntradayPricesBySymbol.merge(prices) { _, refreshed in refreshed }
    }

}



struct HoldingRow: View {
    let position: Position
    let quote: QuoteResponse?
    let intradayPrices: [Double]

    var body: some View {
        HStack(spacing: 10) {
            // 左边：股票信息
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    SymbolLogoView(
                        symbol: position.displaySymbol,
                        crypto: SymbolLogoStore.isCrypto(position.displaySymbol, kind: position.assetClass),
                        size: 20
                    )

                    Text(position.displaySymbol)
                        .font(.headline)
                }

                Text("\(position.quantity, specifier: "%.2f") 股")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: position.quantity)

                Text("市值: $\(position.marketValue, specifier: "%.2f")")
                    .font(.caption)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: position.marketValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.01)
            }

            Spacer(minLength: 6)

            PositionRowSparkline(prices: intradayPrices)
            .frame(width: 72)
            .layoutPriority(0)

            Spacer(minLength: 6)

            // 右边：盈亏 + 成本 + 现价
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(position.pnl >= 0 ? "+" : "")$\(position.pnl, specifier: "%.2f")")
                    .font(.headline)
                    .foregroundStyle(position.pnl >= 0 ? .green : .red)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: position.pnl)
                    .lineLimit(1)
                    .minimumScaleFactor(0.01)

                Text("摊薄成本: $\(position.avgCost, specifier: "%.3f")")
                    .font(.caption)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: position.avgCost)

                Text("现价: $\(quote?.price ?? position.currentPrice, specifier: "%.2f")")
                    .font(.caption)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: quote?.price ?? position.currentPrice)
            }
        }
    }

}

private struct PositionRowSparkline: View {
    let prices: [Double]

    @State private var renderedPrices: [Double] = []
    @State private var previousPrices: [Double] = []
    @State private var refreshBlend = 1.0

    private func lineColor(for prices: [Double]) -> Color {
        guard let first = prices.first,
              let last = prices.last else {
            return .secondary
        }

        return last >= first ? .green : .red
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                sparklineLayer(prices: previousPrices, in: size)
                    .opacity(1 - refreshBlend)

                sparklineLayer(prices: renderedPrices, in: size)
                    .opacity(refreshBlend)
            }
        }
        .frame(height: 42)
        .onAppear {
            renderedPrices = prices
        }
        .onChange(of: prices) { _, newPrices in
            guard renderedPrices != newPrices else { return }

            if renderedPrices.isEmpty {
                renderedPrices = newPrices
                return
            }

            previousPrices = renderedPrices
            renderedPrices = newPrices
            refreshBlend = 0

            withAnimation(.easeInOut(duration: 0.38)) {
                refreshBlend = 1
            }
        }
    }

    @ViewBuilder
    private func sparklineLayer(prices: [Double], in size: CGSize) -> some View {
        if prices.count > 1 {
            let color = lineColor(for: prices)

            areaPath(for: prices, in: size)
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(0.24),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            linePath(for: prices, in: size)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round)
                )
        }
    }

    private func linePath(for prices: [Double], in size: CGSize) -> Path {
        let points = sparklinePoints(for: prices, in: size)

        return Path { path in
            guard let first = points.first else { return }
            path.move(to: first)

            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func areaPath(for prices: [Double], in size: CGSize) -> Path {
        let points = sparklinePoints(for: prices, in: size)

        return Path { path in
            guard let first = points.first,
                  let last = points.last else {
                return
            }

            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)

            for point in points.dropFirst() {
                path.addLine(to: point)
            }

            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }

    private func sparklinePoints(for prices: [Double], in size: CGSize) -> [CGPoint] {
        guard let minPrice = prices.min(),
              let maxPrice = prices.max(),
              size.width > 0,
              size.height > 0 else {
            return []
        }

        let priceRange = max(maxPrice - minPrice, max(abs(maxPrice) * 0.002, 0.01))
        let bottomPadding = size.height * 0.08
        let topPadding = size.height * 0.08
        let drawableHeight = max(size.height - topPadding - bottomPadding, 1)
        let step = size.width / CGFloat(max(prices.count - 1, 1))

        return prices.enumerated().map { index, price in
            let normalized = (price - minPrice) / priceRange
            let y = size.height - bottomPadding - CGFloat(normalized) * drawableHeight
            return CGPoint(x: CGFloat(index) * step, y: y)
        }
    }
}


#Preview {
    PositionsView().environmentObject(PortfolioDemo())
        .modelContainer(for: [Item.self, AssetSnapshotRecord.self, StockLogoRecord.self], inMemory: true)
}
