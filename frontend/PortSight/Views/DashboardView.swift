//
//  DashboardView.swift
//  PortSight
//
//  Created by Chris Cui on 28/4/2026.
//
import SwiftUI
import SwiftData
import Combine
import Foundation
import UIKit

private enum AppSecrets {
    private static let environment = ProcessInfo.processInfo.environment

    static let okxAPIKey = environment["OKX_API_KEY"] ?? ""
    static let okxSecretKey = environment["OKX_SECRET_KEY"] ?? ""
    static let okxPassphrase = environment["OKX_PASSPHRASE"] ?? ""
}

//假的加密货币持仓
struct MockCryptoHolding: Identifiable {
    var id: String { symbol }

    let symbol: String
    let quantity: Double
    let avgCost: Double

    var instId: String {
        "\(symbol)-USDT"
    }
}


struct DashboardView: View {
    @StateObject var vm = AssetViewModel()
    @StateObject private var positionsVM = PositionsViewModel()
    @StateObject private var quoteVM = QuoteViewModel()
    @StateObject private var snapshotsVM = AssetSnapshotsViewModel()
    @StateObject private var marketVM = MarketStatusViewModel()
    
    @StateObject private var okxVM: SpotAccountViewModel
    @StateObject private var logos: LogoStore
    @StateObject private var pricesVM: PricesViewModel
    
    @Binding var selectedTab: Int
    
    init(selectedTab: Binding<Int>) {
        self._selectedTab = selectedTab
        
        let client = OKXClient(
            apiKey: AppSecrets.okxAPIKey,
            secretKey: AppSecrets.okxSecretKey,
            passphrase: AppSecrets.okxPassphrase,
            env: .real
        )
        _okxVM = StateObject(wrappedValue: SpotAccountViewModel(client: client))
        _pricesVM = StateObject(wrappedValue: PricesViewModel())
        _logos = StateObject(wrappedValue: LogoStore(client: client))
    }
    

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var items: [Item]
    @Query(sort: \AssetSnapshotRecord.tradingDate) private var persistedSnapshots: [AssetSnapshotRecord]
    @Query(sort: \StockLogoRecord.ticker) private var stockLogoRecords: [StockLogoRecord]
    
    @State private var selectedAssetValue: Double? = nil
    @State private var lastSyncedLogoSymbolKey = ""
    @State private var canRunServerSync = false
    @State private var hasStartedInitialServerSync = false
    @State private var serverSnapshotDTOs: [AssetSnapshotDTO] = []
    @State private var cachedAssetTrendAnimationFinished = false
    @State private var pendingInitialServerSnapshots: [AssetSnapshotDTO]?
    @State private var pendingInitialServerPositions: [Position]?
    @State private var hasAppliedInitialServerSync = false

    private var snapshotDTOsForChart: [AssetSnapshotDTO] {
        if !serverSnapshotDTOs.isEmpty {
            return serverSnapshotDTOs
        }

        return persistedSnapshots.map(\.dto)
    }

    private var persistedChartSnapshots: [AssetChartSnapshot] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        return snapshotDTOsForChart.compactMap { snapshot in
            guard let date = formatter.date(from: snapshot.tradingDate) else { return nil }
            let noonDate = calendar.date(
                bySettingHour: 12,
                minute: 0,
                second: 0,
                of: date
            ) ?? date

            return AssetChartSnapshot(
                date: noonDate,
                value: snapshot.totalAssets
            )
        }
    }

    private var trendChartSnapshots: [AssetChartSnapshot] {
        guard let firstSnapshot = persistedChartSnapshots.first,
              vm.principalTotal > 0 else {
            return persistedChartSnapshots
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        let principalDate = calendar.date(
            byAdding: .day,
            value: -1,
            to: firstSnapshot.date
        ) ?? firstSnapshot.date

        let principalSnapshot = AssetChartSnapshot(
            date: principalDate,
            value: vm.principalTotal,
            isRecorded: false
        )

        return [principalSnapshot] + persistedChartSnapshots
    }
    
    private var allAssets: [PortfolioAsset] {
        let stockAssets = positionsVM.positions.map { $0.asPortfolioAsset }
        let cryptoAssets = okxVM.spotHoldings.map { $0.asPortfolioAsset }

        //return stockAssets + cryptoAssets
        //真的时候删掉
        return stockAssets + mockCryptoAssets
    }

    private var stockLogoSymbols: [String] {
        Array(Set(positionsVM.positions.map { $0.displaySymbol.uppercased() })).sorted()
    }

    private var top5StockPositions: [Position] {
        positionsVM.positions
            .sorted { $0.marketValue > $1.marketValue }
            .prefix(5)
            .map { $0 }
    }

    private var holdingsCountText: String {
        "\(positionsVM.positions.count) holdings"
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

    private var allocationItems: [AllocationItem] {
        switch allocationFilter {

        // ====================
        // 全部：Cash + >5% + Others
        // ====================
        case .all:
            let cash = cashValue

            let assetItems = allAssets
                .map { AllocationItem(name: $0.symbol, value: $0.marketValue) }
                .sorted { $0.value > $1.value }

            var result: [AllocationItem] = []

            if cash > 0 {
                result.append(.init(name: "Cash", value: cash))
            }

            let maxSingleAssetCount = cash > 0 ? 4 : 5

            let visibleAssets = Array(assetItems.prefix(maxSingleAssetCount))
            let otherAssets = Array(assetItems.dropFirst(maxSingleAssetCount))

            result += visibleAssets

            let othersValue = otherAssets.map(\.value).reduce(0, +)

            if othersValue > 0 {
                result.append(.init(name: "Others", value: othersValue))
            }

            return result.sorted { $0.value > $1.value }


        // ====================
        // 股票：全部股票
        // ====================
        case .stock:
            return positionsVM.positions
                .filter { !$0.isEtf }
                .map {
                    AllocationItem(name: $0.displaySymbol, value: $0.marketValue)
                }
                .sorted { $0.value > $1.value }

        // ====================
        // ETF：全部 ETF
        // ====================
        case .etf:
            return positionsVM.positions
                .filter { $0.isEtf }
                .map {
                    AllocationItem(name: $0.displaySymbol, value: $0.marketValue)
                }
                .sorted { $0.value > $1.value }

        // ====================
        // 加密：全部币
        // ====================
        case .crypto:
            return allAssets
                .filter { $0.type == .crypto }
                .map {
                    AllocationItem(name: $0.symbol, value: $0.marketValue)
                }
                .sorted { $0.value > $1.value }
        }
    }

    
    enum HoldingTab: String, CaseIterable {
        case stock = "股票"
        case crypto = "加密货币"
    }
    
    enum AllocationFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case stock = "股票"
        case etf = "ETF"
        case crypto = "加密货币"

        var id: String { rawValue }
    }

    @State private var selectedHoldingTab: HoldingTab = .stock
    @State private var allocationFilter: AllocationFilter = .all
    
    private var cashValue: Double {
        let stockValue = positionsVM.positions.map(\.marketValue).reduce(0, +)
        return max(vm.totalAsset - stockValue, 0)
    }
    
    private var stockAssets: [PortfolioAsset] {
        allAssets.filter { $0.type == .stock }
    }

    private var cryptoAssets: [PortfolioAsset] {
        allAssets.filter { $0.type == .crypto }
    }

    private var stockValue: Double {
        stockAssets.map(\.marketValue).reduce(0, +)
    }

    private var cryptoValue: Double {
        cryptoAssets.map(\.marketValue).reduce(0, +)
    }
    

    //假的
    private let mockCryptoHoldings: [MockCryptoHolding] = [
        .init(symbol: "BTC", quantity: 0.05, avgCost: 65000),
        .init(symbol: "ETH", quantity: 1.2, avgCost: 3200)
    ]
    private var mockCryptoAssets: [PortfolioAsset] {
        [
            PortfolioAsset(
                type: .crypto,
                symbol: "BTC",
                name: "Bitcoin",
                quantity: 0.05,
                avgCost: 65000,
                currentPrice: 71000,
                prevClosePrice: 71000,
                marketValue: 0.05 * 71000,
                realizedPnL: 0,
                unrealizedPnL: (71000 - 65000) * 0.05,
                pnlRatio: (71000 - 65000) / 65000 * 100,
                currency: "USD",
                source: "mock"
            ),
            PortfolioAsset(
                type: .crypto,
                symbol: "ETH",
                name: "Ethereum",
                quantity: 1.2,
                avgCost: 3200,
                currentPrice: 3600,
                prevClosePrice: 3600,
                marketValue: 1.2 * 3600,
                realizedPnL: 0,
                unrealizedPnL: (3600 - 3200) * 1.2,
                pnlRatio: (3600 - 3200) / 3200 * 100,
                currency: "USD",
                source: "mock"
            )
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                //header渐变颜色
                VStack {
                    HStack(spacing: 0) {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.orange.opacity(0.4),
                                        Color.orange.opacity(0.2),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .offset(x: 60)

                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.blue.opacity(0.4),
                                        Color.blue.opacity(0.2),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .blur(radius: 40)
                    .offset(y: -150)
                    .ignoresSafeArea()
                    .padding(.horizontal, -100)
                    Spacer()
                }

                ScrollView {
                    VStack {
                        Text("1")
                            .font(.system(size: 30))
                            .foregroundStyle(.clear)
                        AssetTrendChart(
                            snapshots: trendChartSnapshots,
                            principal: vm.principalTotal,
                            currentTotalAsset: vm.totalAsset,
                            selectedAssetValue: $selectedAssetValue,
                            onLaunchAnimationFinished: {
                                cachedAssetTrendAnimationFinished = true
                            }
                        )
                        //                    AssetTrendChart(
                        //                        snapshots: testAssetSnapshots,
                        //                        principal: 100_000,
                        //                        selectedAssetValue: $selectedAssetValue
                        //                    )
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .background(Color.clear)
                    .padding(.top, 140)


                    HStack {
                        Picker("", selection: Binding(
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
                        .frame(width: allocationPickerWidth)
                        Spacer()
                    }
                    .padding(.vertical)

                    AllocationDonutChart(
                        items: allocationItems,
                        animationKey: allocationFilter.rawValue
                    )

                    HStack {
                        //显示logo
                        HStack(spacing: -6) {

                            ForEach(Array(top5StockPositions.enumerated()), id: \.element.symbol) { index, position in

                                if let data = stockLogoData(for: position.displaySymbol),
                                   let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .frame(width: 30, height: 30)
                                        .clipShape(Circle())
                                        .zIndex(Double(top5StockPositions.count - index))
                                        .shadow(radius: 3)
                                }
                            }
                        }
                        Text(holdingsCountText)
                            .font(.system(size: 20))
                            .fontWeight(.bold)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .fontWeight(.bold)
                            .font(.system(size: 18))
                    }
                    .onTapGesture {
                        selectedTab = 1
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .task {
                    guard !hasStartedInitialServerSync else { return }

                    hasStartedInitialServerSync = true
                    if cachedAssetTrendAnimationFinished {
                        await prepareInitialServerSync()
                    }
                }
                .onChange(of: cachedAssetTrendAnimationFinished) { _, finished in
                    guard finished else { return }
                    Task {
                        await prepareInitialServerSync()
                    }
                }
                .onDisappear {
                    marketVM.stopPolling()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard canRunServerSync else { return }
                    guard newPhase == .active else { return }

                    Task {
                        await syncAssetSnapshotsForChart()
                    }
                }
                .onChange(of: stockLogoSymbols.joined(separator: "|")) { _, _ in
                    guard canRunServerSync else { return }

                    Task {
                        await syncStockLogosIfNeeded()
                    }
                }
                .onChange(of: hasEtfPositions) { _, hasEtfs in
                    guard !hasEtfs, allocationFilter == .etf else { return }
                    allocationFilter = .all
                }
                .environmentObject(marketVM)
                .navigationBarTitleDisplayMode(.inline)
                .portfolioToolbar(
                    vm: vm,
                    positionsVM: positionsVM,
                    quoteVM: quoteVM,
                    marketVM: marketVM,
                    selectedAssetValue: selectedAssetValue
                )
            }
        }
    }

    private func stockLogoData(for symbol: String) -> Data? {
        let ticker = symbol.uppercased()
        return stockLogoRecords.first { $0.ticker == ticker }?.imageData
    }

    private func prepareInitialServerSync() async {
        guard cachedAssetTrendAnimationFinished else { return }
        guard !hasAppliedInitialServerSync else { return }

        async let snapshotsResult: [AssetSnapshotDTO]? = {
            do {
                return try await snapshotsVM.fetchServerSnapshots()
            } catch {
                return nil
            }
        }()

        async let positionsResult: [Position]? = {
            do {
                return try await positionsVM.fetchServerPositions()
            } catch {
                return nil
            }
        }()

        pendingInitialServerSnapshots = await snapshotsResult
        pendingInitialServerPositions = await positionsResult

        await applyInitialServerSyncIfReady()
    }

    private func applyInitialServerSyncIfReady() async {
        guard cachedAssetTrendAnimationFinished else { return }
        guard !hasAppliedInitialServerSync else { return }

        hasAppliedInitialServerSync = true
        canRunServerSync = true

        if let snapshots = pendingInitialServerSnapshots {
            await applyServerSnapshotsForChart(snapshots)
            pendingInitialServerSnapshots = nil
        }

        if let positions = pendingInitialServerPositions {
            positionsVM.applyPositions(positions)
            await CacheManager.saveAsync(positions, key: "positions_cache_v2")
            pendingInitialServerPositions = nil
        }

        try? await Task.sleep(for: .milliseconds(950))
        guard !Task.isCancelled else { return }

        marketVM.startPolling(every: 20)
        vm.startAutoRefresh(immediately: false)
        await quoteVM.fetchQuotes(
            symbols: positionsVM.positions.map { $0.symbol }
        )
        await syncStockLogosIfNeeded()
        positionsVM.startAutoRefresh(immediately: false)

        let symbols = okxVM.spotHoldings.map { $0.ccy.uppercased() }

        //let instIds = okxVM.spotHoldings.map { $0.instId }
        //pricesVM.start(instIds: instIds, every: 3)
        let cryptoInstIds = ["BTC-USDT", "ETH-USDT"]
        pricesVM.start(instIds: cryptoInstIds, every: 3)
        await okxVM.refresh()

        await logos.load(for: symbols)
    }

    private func syncAssetSnapshotsForChart() async {
        do {
            let serverSnapshots = try await snapshotsVM.fetchServerSnapshots()
            await applyServerSnapshotsForChart(serverSnapshots)
        } catch {
            snapshotsVM.errorMessage = error.localizedDescription
            print("sync asset snapshots error:", error)
        }
    }

    private func applyServerSnapshotsForChart(_ serverSnapshots: [AssetSnapshotDTO]) async {
        guard !serverSnapshots.isEmpty else { return }

        let serverSignature = snapshotDTOSignature(serverSnapshots)
        let shouldUpdateChart = snapshotDTOChartSignature(snapshotDTOsForChart) != snapshotDTOChartSignature(serverSnapshots)
        let shouldPersist = snapshotDTOSignature(persistedSnapshots.map(\.dto)) != serverSignature

        if shouldUpdateChart {
            serverSnapshotDTOs = serverSnapshots
        }

        guard shouldPersist else { return }

        try? await Task.sleep(for: .milliseconds(1150))
        guard !Task.isCancelled else { return }

        try? snapshotsVM.replacePersistedSnapshots(serverSnapshots, modelContext: modelContext)
        await CacheManager.saveAsync(serverSnapshots, key: "asset_snapshots_cache")
    }

    private func snapshotDTOSignature(_ snapshots: [AssetSnapshotDTO]) -> String {
        snapshots.map {
            "\($0.tradingDate)-\($0.recordedAt)-\($0.totalAssets)-\($0.principal)"
        }.joined(separator: "|")
    }

    private func snapshotDTOChartSignature(_ snapshots: [AssetSnapshotDTO]) -> String {
        snapshots.map {
            "\($0.tradingDate)-\($0.totalAssets)-\($0.principal)"
        }.joined(separator: "|")
    }

    private func syncStockLogosIfNeeded() async {
        let symbols = stockLogoSymbols
        let symbolKey = symbols.joined(separator: "|")
        guard !symbols.isEmpty, symbolKey != lastSyncedLogoSymbolKey else { return }

        await syncStockLogoRecords(
            symbols: symbols,
            records: stockLogoRecords,
            modelContext: modelContext
        )
        lastSyncedLogoSymbolKey = symbolKey
    }
}





struct CryptoHoldingRow: View {
    let holding: MockCryptoHolding
    let price: Double?

    private var currentPrice: Double {
        price ?? 0
    }

    private var marketValue: Double {
        holding.quantity * currentPrice
    }

    private var pnl: Double {
        (currentPrice - holding.avgCost) * holding.quantity
    }

    private var pnlRatio: Double {
        holding.avgCost > 0 ? (currentPrice - holding.avgCost) / holding.avgCost * 100 : 0
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.symbol)
                    .font(.headline)

                Text("\(holding.quantity, specifier: "%.4f") 枚")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("市值: $\(marketValue, specifier: "%.2f")")
                    .font(.caption)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: marketValue)
            }

            Spacer()
            
            Text("图表")
            
            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(pnl >= 0 ? "+" : "-")$\(abs(pnl), specifier: "%.2f")")
                    .font(.headline)
                    .foregroundStyle(pnl >= 0 ? .green : .red)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: pnl)

                Text("\(pnlRatio >= 0 ? "+" : "-")\(abs(pnlRatio), specifier: "%.2f")%")
                    .font(.caption)
                    .foregroundStyle(pnl >= 0 ? .green : .red)

                Text("现价: $\(currentPrice, specifier: "%.2f")")
                    .font(.caption)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: currentPrice)
            }
        }
    }
}



#Preview {
    ContentView()
        .modelContainer(for: [Item.self, AssetSnapshotRecord.self, StockLogoRecord.self], inMemory: true)
}

#Preview {
    DashboardView(selectedTab: .constant(0))
        .modelContainer(for: [Item.self, AssetSnapshotRecord.self, StockLogoRecord.self], inMemory: true)
}

//加密货币真实数据用这个
//                    ForEach(okxVM.spotHoldings) { detail in
//                            NavigationLink {
//                                AssetDetailView(asset: detail.asPortfolioAsset)
//                            } label: {
//                                CryptoHoldingRow(
//                                    holding: MockCryptoHolding(
//                                        symbol: detail.ccy,
//                                        quantity: detail.quantity,
//                                        avgCost: detail.avgCost
//                                    ),
//                                    price: pricesVM.price(for: detail.instId)
//                                )
//                            }
//                        }
