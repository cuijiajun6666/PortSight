import Foundation
import Testing
@testable import PortSightKit

struct PortSightKitTests {
    /// Demo mode keeps everything offline except the relay: unpaired, the server page shows the sample and
    /// nothing is requested; a plain-http address is refused before any request is built.
    @Test func demoModeShowsTheSampleUntilPaired() async {
        #expect(DemoPortfolioData.enabled)
        UserDefaults.standard.removeObject(forKey: ServerStore.urlKey)
        let store = ServerStore()
        #expect(store.isSample && store.pairingState == .unpaired)
        #expect(await store.refresh() == false)
        #expect(await store.pair(url: "http://" + TerminalPlaceholders.host, code: "123456") == false)
        #expect(store.pairingState == .unpaired)
    }

    @Test func offlineGuardLetsOnlyRelayRequestsThrough() throws {
        let base = "https://mac-mini.xxxx.ts.net"
        #expect(DemoOfflineProtocol.canInit(with: URLRequest(url: URL(string: base + "/devices")!)))
        let pair = try #require(RelayAPI.pairingRequest(base: base, code: "1", apnsToken: ""))
        let read = try #require(RelayAPI.readRequest(base: base, endpoint: .host, deviceToken: "t"))
        #expect(!DemoOfflineProtocol.canInit(with: pair) && !DemoOfflineProtocol.canInit(with: read))
    }

    @Test func sampleHostShowsTheFourPlannedVolumes() {
        let volumes = StorageVolume.volumes(from: ServerSample.host)
        #expect(volumes.map(\.key) == ["internal", "main", "backup", "photos"])
        #expect(volumes.first { $0.key == "main" }?.mounted == true)
        #expect(volumes.first { $0.key == "photos" }?.mounted == false)
    }

    @Test func relayAddressMustBeAnHTTPSOrigin() {
        #expect(ServerStore.normalizedURL("https://Mac-Mini.xxxx.ts.net/") == "https://mac-mini.xxxx.ts.net")
        #expect(ServerStore.normalizedURL("http://mac-mini.xxxx.ts.net") == nil)
        #expect(ServerStore.normalizedURL("https://mac-mini.xxxx.ts.net/path") == nil)
    }

    @Test func alertFiltersAndReadState() {
        let terminal = TerminalDemo(followsRelay: false)
        terminal.read = []
        #expect(terminal.unreadCount == terminal.alerts.count)
        terminal.severity = .critical
        #expect(terminal.filtered.allSatisfy { $0.severity == .critical })
        terminal.markAllRead()
        #expect(terminal.unreadCount == 0)
    }

    @Test func everySectionHasAFilledSymbol() {
        for section in TerminalSection.allCases {
            #expect(section.selectedIcon == section.icon + ".fill")
        }
    }

    /// Plan §5: the only POSTs allowed towards the relay are POST /devices (pairing) and POST /ibkr/reauth (asks the
    /// Mac mini to start the IBKR login; the one action the quant session allows). DriveAPI.swift is the one exception:
    /// it builds the Google Drive upload requests (token POST, resumable POST + PUTs) and may never DELETE,
    /// PATCH or list files (contract: the app only uploads; the Mac mini deletes).
    @Test func onlyPOSTIsDevicePairing() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        var writes: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            if file.lastPathComponent == "DriveAPI.swift" {
                for verb in ["\"DELETE\"", "\"PATCH\"", "\"GET\""] where text.contains(verb) { writes.append("DriveAPI.swift " + verb) }
                continue
            }
            for verb in ["\"PUT\"", "\"DELETE\"", "\"PATCH\""] where text.contains(verb) { writes.append(file.lastPathComponent + " " + verb) }
            // RelayAPI.swift builds the relay requests; its POSTs go to /devices and /ibkr/reauth only.
            if text.contains("\"POST\"") && file.lastPathComponent != "RelayAPI.swift" { writes.append(file.lastPathComponent + " POST") }
            if file.lastPathComponent == "RelayAPI.swift" {
                let posts = text.components(separatedBy: "\"POST\"").count - 1
                if posts != 2 || !text.contains("base + \"/devices\"") || !text.contains("base + \"/ibkr/reauth\"") {
                    writes.append("RelayAPI.swift POST outside /devices and /ibkr/reauth")
                }
            }
        }
        #expect(writes.isEmpty, "\(writes)")
    }
}

struct PhotoUploadQueueTests {
    private func makeFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("upload-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("旅行/第一天")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10).write(to: root.appendingPathComponent("a.jpg"))
        try Data(repeating: 1, count: 20).write(to: nested.appendingPathComponent("b.heic"))
        try Data(repeating: 1, count: 30).write(to: nested.appendingPathComponent("c.mov"))
        try Data("notes".utf8).write(to: nested.appendingPathComponent("notes.txt"))
        return root
    }

    @Test func folderDropFindsPhotosAndVideosRecursively() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let queue = PhotoUploadQueue()
        #expect(queue.add([folder]) == 3)
        #expect(queue.photoCount == 2)
        #expect(queue.videoCount == 1)
        #expect(queue.skipped == 1)
        #expect(queue.totalBytes == 60)
        // Dropping the same folder again adds nothing and does not count its skipped files twice.
        #expect(queue.add([folder]) == 0)
        #expect(queue.items.count == 3)
        #expect(queue.skipped == 1)
        #expect(queue.message == "这些文件已经在队列里了")
        // Emptying the queue item by item also resets the skip count.
        for item in queue.items { queue.remove(item) }
        #expect(queue.skipped == 0)
    }

    @Test func photosAppPromisesAreCopiedBeforeQueueing() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = try #require(PhotoUploadQueue.keepImportedCopy(of: folder.appendingPathComponent("a.jpg"), suggestedName: "IMG_0001"))
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        #expect(copy.lastPathComponent == "IMG_0001.jpg")
        let queue = PhotoUploadQueue()
        #expect(queue.add([copy]) == 1)
    }

    @Test func demoModeNeverUploads() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let queue = PhotoUploadQueue()
        queue.add([folder])
        queue.start()
        #expect(queue.items.allSatisfy { $0.state == .waiting })
        #expect(queue.message?.contains("后台上传") == true)
    }

    @Test func feedMergesNoticesAndAlerts() {
        let items = NotificationFeed.items(notices: DemoPortfolioData.notices, alerts: DemoTerminalData.alerts)
        #expect(items.count == DemoPortfolioData.notices.count + DemoTerminalData.alerts.count)
        #expect(Set(items.map(\.id)).count == items.count)
        #expect(items.allSatisfy { NotificationFeed.categories.contains($0.category) })
    }
}

struct FamilyVaultTests {
    @Test func passcodeFormatIsSixDigits() {
        #expect(VaultPasscode.isValidFormat("135790"))
        #expect(!VaultPasscode.isValidFormat("12345"))
        #expect(!VaultPasscode.isValidFormat("12345a"))
    }

    @Test func vaultStaysOpenWithinGracePeriod() {
        var clock = Date(timeIntervalSince1970: 0)
        let session = VaultSession(now: { clock })
        session.appeared()
        session.unlock()
        session.disappeared()                       // switched to another tab
        clock += VaultSession.grace - 10
        session.appeared()
        #expect(session.isUnlocked)

        session.appWentToBackground()
        clock += VaultSession.grace + 1
        session.appBecameActive()
        #expect(!session.isUnlocked)
    }

    @Test func pushingADocumentDoesNotStartTheGracePeriod() {
        var clock = Date(timeIntervalSince1970: 0)
        let session = VaultSession(now: { clock })
        session.appeared()
        session.unlock()
        session.appeared()                          // document pushed
        session.disappeared()                       // vault list hidden behind it
        clock += VaultSession.grace * 3
        session.appeared()
        session.disappeared()                       // back to the list
        #expect(session.isUnlocked)
        session.lock()
        #expect(!session.isUnlocked)
    }

    @Test func vaultAnswersPointAtTheirDocuments() {
        let answer = DemoVaultData.answer("爸爸的护照什么时候到期？")
        #expect(answer?.documentIDs == ["passport-dad"])
        #expect(DemoVaultData.expiringSoon.allSatisfy { ($0.daysToExpiry() ?? .max) <= 90 })
    }

    @Test func familySearchFindsSunsetsAndConnectionReadsAsRelayed() {
        #expect(DemoFamilyData.search("海边的日落").contains { $0.id == "p11" })
        #expect(DemoConnection.family.path == .relayed)
        #expect(DemoConnection.family.speedTitle == "正常")
    }
}

@MainActor
struct BacktestTests {
    @Test func sampleRunsHaveTradesOfEveryKind() {
        let runs = BacktestSample.runs()
        #expect(runs.count == 3)
        let run = runs[0]
        #expect(run.trades.count > 50)
        let reasons = Set(runs.flatMap(\.trades).map(\.exitReason))
        #expect(reasons.isSuperset(of: ["stop_loss", "signal_exit", "take_profit"]))
        #expect(run.trades.contains { $0.stops.count > 1 })
        #expect(run.trades.allSatisfy { $0.targets.isEmpty })
        #expect(runs[1].trades.contains { !$0.targets.isEmpty })
        #expect(run.trades.contains { $0.sizePath.contains { $0.why == "add" } })
        #expect(!run.bars("BTCUSDT", .h4).isEmpty)
        #expect(run.bars("BTCUSDT", .m15).count == run.bars("BTCUSDT", .h1).count * 4)
        #expect(!BacktestQuickFilter.reopened.apply(run.trades).isEmpty)
    }

    @Test func metricsFromAKnownCurve() {
        // Doubling over exactly one year with a 20% dip.
        let day = 86_400_000.0
        func nav(_ i: Int) -> Double {
            if i <= 100 { return 1 + Double(i) * 0.005 }
            if i <= 120 { return 1.5 * (1 - Double(i - 100) * 0.01) }
            return 1.2 + Double(i - 120) * 0.8 / 245
        }
        var equity: [BacktestEquityPoint] = []
        for i in 0...365 { equity.append(BacktestEquityPoint(t: Double(i) * day, nav: nav(i), dd: 0, benchNav: nil)) }
        let metrics = BacktestMetrics(trades: [], equity: equity)
        #expect(abs(metrics.overall.annualReturn - 1.0) < 0.01)
        #expect(abs(metrics.overall.maxDrawdown + 0.2) < 0.001)
        #expect(metrics.overall.sharpeLow < metrics.overall.sharpe && metrics.overall.sharpe < metrics.overall.sharpeHigh)
    }

    @Test func loaderReadsTheExportFormatAndDropsTheSealedPeriod() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "bt-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appending(path: "bars"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appending(path: "signals"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sealed = BacktestRun.sealStart.milliseconds + 3_600_000
        func write(_ file: String, _ json: String) throws { try json.write(to: folder.appending(path: file), atomically: true, encoding: .utf8) }
        try write("meta.json", #"{"run_id":"r1","strategy":"v4","protocol_sha":"abc","segment":"discovery","start":0,"end":1,"verdict":"selected","cost_model":"5bp","notes":null}"#)
        try write("trades.json", """
        [{"id":"T1","symbol":"BTCUSDT","side":"long","entry_t":1641000000000,"entry_px":47000,"exit_t":1641090000000,"exit_px":47800,"exit_reason":"signal_exit","size_path":[{"t":1641000000000,"w":0.05,"why":"open"}],"stops":[],"targets":[],"pnl_gross":0.0021,"fee":0.0004,"funding":-0.0001,"pnl_net":0.0016,"mfe":0.003,"mae":-0.0012,"hold_h":25,"signals_at_entry":{"mu_4h":0.0012}},
         {"id":"T2","symbol":"BTCUSDT","side":"short","entry_t":\(sealed),"entry_px":1,"exit_t":\(sealed + 1),"exit_px":1,"exit_reason":"x","pnl_net":0.5}]
        """)
        try write("equity.json", #"[{"t":1641000000000,"nav":1.0,"dd":0.0,"bench_nav":1.0}]"#)
        try write("bars/BTCUSDT_1h.json", #"[{"t":1641000000000,"o":1,"h":2,"l":0.5,"c":1.5,"v":10}]"#)
        try write("signals/BTCUSDT.json", #"[{"t":1641000000000,"mu_4h":0.0012,"entry_thr":0.001}]"#)

        let run = try BacktestLoader.load(directory: folder)
        #expect(run.meta.runID == "r1")
        #expect(run.trades.map(\.id) == ["T1"])
        #expect(run.symbols == ["BTCUSDT"])
        #expect(run.timeframes("BTCUSDT") == [.h1])
        #expect(run.signals("BTCUSDT").first?.values["entry_thr"] == 0.001)
        #expect(run.trades[0].exitTitle == "信号退出")
    }
}

@MainActor
struct MarketHeatmapTests {
    private func aspect(_ r: CGRect) -> Double { Double(max(r.width, r.height) / min(r.width, r.height)) }

    private func overlaps(_ rects: [CGRect]) -> Bool {
        for i in rects.indices {
            for j in rects.indices where j > i {
                let both = rects[i].intersection(rects[j])
                if !both.isNull && both.width > 0.001 && both.height > 0.001 { return true }
            }
        }
        return false
    }

    @Test func squarifiedAreasFillTheRectWithoutOverlap() {
        let rect = CGRect(x: 10, y: 20, width: 640, height: 320)
        let weights = DemoMarketHeatmap.stocks.map(\.marketCap)
        let rects = Treemap.squarify(weights, in: rect)
        #expect(rects.count == weights.count)
        let area = rects.reduce(0) { $0 + $1.width * $1.height }
        #expect(abs(area - rect.width * rect.height) < 0.5)
        #expect(!overlaps(rects))
        #expect(rects.allSatisfy { rect.insetBy(dx: -0.001, dy: -0.001).contains($0) })
        // Each tile's area is proportional to its weight.
        let total = weights.reduce(0, +)
        for (weight, r) in zip(weights, rects) {
            #expect(abs(Double(r.width * r.height) - weight / total * Double(rect.width * rect.height)) < 0.5)
        }
    }

    @Test func squarifiedAspectRatiosStayReasonable() {
        let equal = Treemap.squarify(Array(repeating: 1, count: 16), in: CGRect(x: 0, y: 0, width: 400, height: 400))
        #expect(equal.allSatisfy { abs(aspect($0) - 1) < 0.01 })
        let rect = CGRect(x: 0, y: 0, width: 800, height: 400)
        let sectors = Treemap.squarify(DemoMarketHeatmap.sectors.map(\.marketCap), in: rect)
        #expect(sectors.allSatisfy { aspect($0) < 4 })
        let rects = Treemap.squarify(DemoMarketHeatmap.stocks.map(\.marketCap), in: rect)
        let totalArea = Double(rect.width * rect.height)
        let weighted = rects.reduce(0.0) { $0 + aspect($1) * Double($1.width * $1.height) } / totalArea
        #expect(weighted < 2)
    }

    @Test func squarifyHandlesEmptyAndZeroWeights() {
        #expect(Treemap.squarify([], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
        let rects = Treemap.squarify([3, 0, -1, 1], in: CGRect(x: 0, y: 0, width: 40, height: 10))
        #expect(rects[1] == .zero && rects[2] == .zero)
        #expect(abs(rects[0].width * rects[0].height - 300) < 0.01)
        #expect(abs(rects[3].width * rects[3].height - 100) < 0.01)
        #expect(Treemap.squarify([1, 2], in: .zero).allSatisfy { $0 == .zero })
    }

    @Test func nestedLayoutKeepsTilesInsideTheirSector() {
        let rect = CGRect(x: 0, y: 0, width: 720, height: 340)
        let layout = HeatmapLayout(sectors: DemoMarketHeatmap.sectors, in: rect, headerHeight: 18, sectorGap: 3)
        #expect(layout.sectors.count == DemoMarketHeatmap.sectors.count)
        #expect(layout.tiles.count == DemoMarketHeatmap.stocks.count)
        #expect(!overlaps(layout.sectors.map(\.frame)))
        #expect(!overlaps(layout.tiles.map(\.frame)))
        for sector in layout.sectors {
            #expect(rect.contains(sector.frame))
            if let header = sector.header { #expect(!header.intersects(sector.body)) }
            let tiles = layout.tiles.filter { $0.sectorID == sector.id }
            let area = tiles.reduce(0) { $0 + $1.frame.width * $1.frame.height }
            #expect(abs(area - sector.body.width * sector.body.height) < 0.5)
            #expect(tiles.allSatisfy { sector.body.insetBy(dx: -0.001, dy: -0.001).contains($0.frame) })
        }
        let nvda = layout.tiles.first { $0.stock.symbol == "NVDA" }
        #expect(nvda.map { layout.tile(at: CGPoint(x: $0.frame.midX, y: $0.frame.midY))?.stock.symbol } == "NVDA")
    }

    @Test func colorScaleIsDivergingAndClamped() {
        let scale = HeatmapColorScale()
        #expect(scale.intensity(0) == 0)
        #expect(scale.intensity(0.015) == 0.5)
        #expect(scale.intensity(-0.015) == -0.5)
        #expect(scale.intensity(0.08) == 1)
        #expect(scale.intensity(-0.2) == -1)
        #expect(HeatmapFormat.change(0.0219) == "+2.19%")
        #expect(HeatmapFormat.marketCap(4_400) == "4.40 万亿美元")
        #expect(HeatmapFormat.netFlow(-35) == "−3,500 万美元")
        #expect(Set(DemoMarketHeatmap.stocks.map(\.symbol)).count == DemoMarketHeatmap.stocks.count)
    }
}

struct LiveFeedTests {
    private static let start = Date(timeIntervalSince1970: 1_794_000_000) // 2026-11-06 UTC

    /// The pages share one feed, built once in the background (prepare() and shared() reuse the same build).
    @Test func sharedFeedIsBuiltOnceInTheBackground() async {
        LiveFeed.prepare()
        let a = await LiveFeed.shared()
        let b = await LiveFeed.shared()
        #expect(a === b)
        #expect(!a.fills.isEmpty)
        #expect(!a.bars("BTCUSDT", .m5).isEmpty)
    }

    /// Two pages on the shared feed: the clock keeps running until the last one leaves.
    @Test func clockRunsWhileAnyPageIsOnScreen() {
        let feed = LiveFeed(seed: 7, now: Date())
        feed.stop(for: "unknown")                       // a page that never started: ignored
        #expect(!feed.isRunning)
        feed.start(for: "a")
        feed.start(for: "b")
        #expect(feed.isRunning)
        feed.stop(for: "b")
        #expect(feed.isRunning)
        feed.stop(for: "b")                             // twice: still running for "a"
        #expect(feed.isRunning)
        feed.stop(for: "a")
        #expect(!feed.isRunning)
    }

    @Test func sameSeedGivesTheSameHistoryAndFirstTicks() {
        let a = LiveFeed(seed: 42, now: Self.start)
        let b = LiveFeed(seed: 42, now: Self.start)
        #expect(a.marks == b.marks)
        #expect(a.fills == b.fills)
        #expect(a.positions == b.positions)
        for step in 1...5 {
            let date = Self.start.addingTimeInterval(Double(step) * LiveFeed.tickInterval)
            a.tick(at: date)
            b.tick(at: date)
            #expect(a.marks == b.marks)
            #expect(a.bars("BTCUSDT", .m1).last == b.bars("BTCUSDT", .m1).last)
            #expect(a.accounts == b.accounts)
        }
        #expect(a.now == Self.start.addingTimeInterval(5 * LiveFeed.tickInterval).milliseconds)
        // History: 14 days of 5-minute bars, the last two days of 1-minute bars, closed trades and open positions.
        #expect(a.bars("ETHUSDT", .m5).count >= 14 * 288)
        #expect(a.bars("BTCUSDT", .m1).count <= 2 * 1_440 + 2)
        #expect(!a.closedTrades.isEmpty)
        #expect(!a.positions.isEmpty)
        #expect(LiveFeed(seed: 43, now: Self.start).marks["BTCUSDT"] != nil)
    }

    @Test func shortPositionGainsWhenThePriceFalls() {
        var short = LivePosition(id: "P1", accountId: "paper-1", model: "m", contract: "BTCUSDT", side: .short,
                                 size: 0.5, leverage: 5, entryPx: 70_000, markPx: 70_000, stopPx: 71_000,
                                 targetPx: 68_000, openedAt: 0, tradeId: "T1")
        short.revalue(mark: 69_000)
        #expect(short.unrealizedPnl == 500)
        #expect(short.unrealizedPct > 0)
        short.revalue(mark: 70_500)
        #expect(short.unrealizedPnl == -250)
        #expect(short.unrealizedPct < 0)
        let trade = short.chartTrade(now: 3_600_000, equity: 100_000)
        #expect(trade.side == .short && trade.exitPx == 70_500 && !trade.isWin)
    }

    @Test func shadowLedgerExposesNoMoney() throws {
        let feed = LiveFeed(seed: 7, now: Self.start)
        let shadow = try #require(feed.account(.shadow))
        #expect(shadow.equity == nil && shadow.balance == nil && shadow.todayPnl == nil && shadow.unrealizedPnl == nil)
        #expect(!feed.positions.contains { $0.accountId == shadow.id })
        #expect(!feed.fills.contains { $0.accountId == shadow.id })
        #expect(!feed.closedTrades.contains { $0.accountId == shadow.id })
        #expect(feed.models.filter { $0.accountId == shadow.id }.allSatisfy { $0.signals.isEmpty && !$0.checks.isEmpty })

        let viewer = LiveViewerModel(feed: feed)
        viewer.accountKind = .shadow
        #expect(viewer.positions.isEmpty && viewer.fills.isEmpty && viewer.chartTrades.isEmpty && viewer.openPositions.isEmpty)

        // A feed that sends money for the shadow ledger anyway is sealed on read.
        var snapshot = feed.snapshot()
        snapshot.accounts = snapshot.accounts.map {
            LiveAccount(id: $0.id, kind: $0.kind, name: $0.name, balance: 1, equity: 1, available: 1, marginUsed: 0,
                        todayPnl: 1, unrealizedPnl: 0, updatedAt: $0.updatedAt)
        }
        let sealed = snapshot.sealed()
        #expect(sealed.accounts.first { $0.kind == .shadow }?.equity == nil)
        #expect(sealed.accounts.first { $0.kind == .paper }?.equity == 1)
    }

    @Test func liveModelsRoundTripWithSnakeCaseKeys() throws {
        let feed = LiveFeed(seed: 3, now: Self.start)
        let data = try JSONEncoder().encode(feed.snapshot())
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"margin_used\"") && json.contains("\"entry_px\"") && json.contains("\"closed_trades\""))
        let decoded = try JSONDecoder().decode(LiveSnapshot.self, from: data)
        #expect(decoded.positions == feed.snapshot().positions)
    }

    /// Clicking a box that is partly off screen moves the window so the whole trade shows; one already in full view
    /// keeps the window as it is; a click on empty space clears the selection.
    @Test func clickingATradeShowsAllOfIt() throws {
        let viewer = LiveViewerModel(feed: LiveFeed(seed: 5, now: Self.start))
        // 15-minute bars reach back the whole 14 days; a trade that ended days ago keeps the window off the live edge.
        viewer.changeTimeframe(.m15)
        let old: Double = viewer.feed.now - 3 * 86_400_000
        let contract = viewer.contract
        let candidates: [BacktestTrade] = viewer.trades.map(\.trade).filter { trade in
            trade.symbol == contract && trade.exitT > trade.entryT && trade.exitT < old
        }
        func distance(_ trade: BacktestTrade) -> Double { abs((trade.exitT - trade.entryT) - 4 * 3_600_000) }
        let trade = try #require(candidates.min { distance($0) < distance($1) })
        let length = trade.exitT - trade.entryT

        // Window starting at the entry: the box's left part (and its padding) is cut off.
        viewer.setWindow(center: trade.entryT + length * 1.5, width: length * 3)
        #expect(viewer.window.lowerBound > trade.entryT - length * 0.12)
        viewer.select(trade)
        #expect(viewer.selectedTradeID == trade.id)
        #expect(viewer.window.lowerBound <= trade.entryT && viewer.window.upperBound >= trade.exitT)

        // Already in full view: nothing moves.
        viewer.setWindow(center: (trade.entryT + trade.exitT) / 2, width: length * 4)
        let before = viewer.window
        viewer.select(trade)
        #expect(viewer.window == before)

        viewer.select(nil)
        #expect(viewer.selectedTradeID == nil)
    }

    /// Clicking an open position whose entry is off screen widens the window and keeps following the newest bar,
    /// so the position's live end stays in view.
    @Test func clickingAnOpenPositionKeepsFollowing() throws {
        let viewer = LiveViewerModel(feed: LiveFeed(seed: 5, now: Self.start))
        let now = viewer.feed.now
        let position = try #require(viewer.positions.filter { now - $0.openedAt > 2 * 3_600_000 }.min { $0.openedAt < $1.openedAt })
        viewer.changeContract(position.contract)
        viewer.changeTimeframe(.m1)
        // 30 one-minute candles at the live edge: the entry hours ago is off the left edge.
        viewer.setWindow(center: viewer.window.upperBound, width: 1)
        #expect(viewer.followsLatest && viewer.window.lowerBound > position.openedAt)

        viewer.select(position.chartTrade(now: now, equity: viewer.account?.equity ?? 1))
        #expect(viewer.selectedTradeID == position.tradeId)
        #expect(viewer.followsLatest)
        #expect(viewer.window.lowerBound <= position.openedAt && viewer.window.upperBound >= now)

        // Panned away, then clicked again: back to following, still covering the entry.
        viewer.pan(by: -viewer.span / 2)
        #expect(!viewer.followsLatest)
        viewer.select(position.chartTrade(now: now, equity: viewer.account?.equity ?? 1))
        #expect(viewer.followsLatest && viewer.window.lowerBound <= position.openedAt)
    }

    @Test func liveChartFollowsTheNewestBarUntilPannedAway() {
        let viewer = LiveViewerModel(feed: LiveFeed(seed: 5, now: Self.start))
        #expect(viewer.followsLatest)
        let edge = viewer.window.upperBound
        viewer.pan(by: -viewer.span)
        #expect(!viewer.followsLatest)
        #expect(viewer.window.upperBound < edge)
        viewer.goToLatest()
        #expect(viewer.followsLatest && viewer.window.upperBound == edge)
    }
}

// MARK: - Real exported backtests (real-data)

@MainActor
struct BacktestExportFormatTests {
    @Test func tradesDecodeWithNullPricesMissingFieldsAndExtraKeys() throws {
        let json = """
        [{"id":"T1","symbol":"LUNAUSDT","side":"long","entry_t":1649116800000,"entry_px":80.1,"exit_t":1652745600000,"exit_px":null,
          "exit_reason":"rebalance_exit","size_path":[{"t":1649116800000,"w":0.05,"why":"open"}],"stops":[],"targets":[],
          "pnl_gross":-0.01,"fee":0.0001,"funding":0,"pnl_net":-0.0101,"mfe":0.001,"mae":-0.02,"hold_h":1008},
         {"id":"T2","symbol":"AKROUSDT","side":"short","entry_t":1611187200000,"entry_px":0.01741,"exit_t":1612483200000,"exit_px":0.04085,
          "exit_reason":"liquidated","size_path":[{"t":1611187200000,"w":-0.05,"why":"open"},{"t":1612483200000,"w":0.0,"why":"close"}],
          "stops":[],"targets":[],"hedge":{"symbol":"BTCUSDT","side":"long","w":0.05,"entry_px":35500.0,"exit_px":36976.93},
          "pnl_net":-0.05,"fee":0.0001,"mfe":0.004,"mae":-0.05,"hold_h":360.0,"signals_at_entry":{"days_since_listing":1.0,"flag":null},
          "entered_in_lockbox":false,"slot_return":-1.0},
         {"id":"T3","symbol":"ETHUSDT","side":"long","entry_t":1641129300000,"entry_px":3744.3,"exit_t":1641172500000,"exit_px":3798.64,
          "exit_reason":"time","size_path":[{"t":1641129300000,"w":0.1,"why":"open"},{"t":1641143700000,"w":0.05,"why":"reduce"},
          {"t":1641172500000,"w":0.0,"why":"close"}],"stops":[{"t":1641129300000,"px":3591.668}],
          "targets":[{"t":1641129300000,"px":3795.177}],"pnl_net":0.0016,"hold_h":12.0,"extensions":0},
         {"symbol":"BROKEN"}]
        """
        let trades = try JSONDecoder().decode(LossyArray<BacktestTrade>.self, from: Data(json.utf8))
        #expect(trades.items.count == 3 && trades.skipped == 1)
        let (rebalance, liquidated, halfTP) = (trades.items[0], trades.items[1], trades.items[2])

        #expect(!rebalance.hasPrices && rebalance.exitPrice == nil && rebalance.exitPx.isNaN)
        #expect(rebalance.exitPriceText == "—" && rebalance.knownPriceReturn == nil)
        #expect(rebalance.exitTitle == "调仓退出")
        #expect(liquidated.exitTitle == "强平" && liquidated.reportedPnlGross == nil && liquidated.reportedFunding == nil)
        #expect(liquidated.hedge?.symbol == "BTCUSDT" && liquidated.enteredInLockbox == false)
        #expect(liquidated.signalsAtEntry == ["days_since_listing": 1.0])
        #expect(halfTP.reportedMfe == nil && halfTP.signalsAtEntry.isEmpty && halfTP.extensions == 0)

        // The target stops at the half take-profit instead of running on to the exit.
        #expect(halfTP.halfTakeProfitT == 1641143700000)
        #expect(halfTP.steps(halfTP.targets).last?.to == 1641143700000)
        #expect(halfTP.steps(halfTP.stops).last?.to == halfTP.exitT)
        #expect(halfTP.title(of: halfTP.sizePath[1]) == "半仓止盈")

        for (raw, title) in [("data_end", "数据结束"), ("signal_flip", "信号反转"), ("max_hold", "最长持有"),
                             ("delist_settlement", "下架结算"), ("path_ended", "下架结算"), ("stop", "止损"), ("time", "到期")] {
            #expect(BacktestExitReason.title(raw) == title)
        }

        // Unpriced trades are never drawn but stay in the trade list.
        let encoded = try JSONEncoder().encode(rebalance)
        let decoded = try JSONDecoder().decode(BacktestTrade.self, from: encoded)
        #expect(decoded == rebalance)
    }

    @Test func weeklyEquityIsAnnualisedByItsOwnSpacing() {
        let week = 7 * 86_400_000.0
        let equity = (0...104).map { i in
            BacktestEquityPoint(t: Double(i) * week, nav: 1 + Double(i) * 0.002 + (i % 2 == 0 ? 0.004 : 0), dd: 0, benchNav: nil)
        }
        let metrics = BacktestMetrics(trades: [], equity: equity)
        #expect(metrics.stepDays == 7 && metrics.samplingTitle == "周")
        let daily = BacktestMetrics(trades: [], equity: equity.enumerated().map {
            BacktestEquityPoint(t: Double($0.offset) * 86_400_000, nav: $0.element.nav, dd: 0, benchNav: nil)
        })
        // Same returns: weekly spacing scales Sharpe by √(365/7) instead of √365.
        #expect(abs(metrics.overall.sharpe * 7.0.squareRoot() - daily.overall.sharpe) < 1e-9)
    }

    static let realRoot = URL(filePath: "/Users/chriscui/Desktop/PortSightBacktests", directoryHint: .isDirectory)

    @Test func realExportedRunsAllDecode() async throws {
        guard FileManager.default.fileExists(atPath: Self.realRoot.appending(path: "index.json").path()) else { return }
        #expect(BacktestLoader.isRunCollection(Self.realRoot))
        let (runs, failures) = try BacktestLoader.loadAll(from: Self.realRoot)
        #expect(failures.isEmpty)
        #expect(runs.count == 13)
        for run in runs {
            #expect(!run.isLoaded)
            #expect(run.loadError == nil && run.skippedTrades == 0, "\(run.id): \(run.loadError ?? "")")
            #expect(run.trades.count == run.meta.tradeCount, "\(run.id)")
            #expect(!run.equity.isEmpty && run.equity.allSatisfy { $0.t < BacktestRun.sealStart.milliseconds })
            #expect(!run.symbols.isEmpty)
        }
        // The arm-0 samples the quant system exported directly: no fixed stops or targets, volume left null.
        let g263 = try #require(runs.first { $0.id == "g263_ema1h_vol10" })
        let g210 = try #require(runs.first { $0.id == "g210_a04_b15_vol10" })
        #expect(runs.prefix(2).map(\.id) == ["g263_ema1h_vol10", "g210_a04_b15_vol10"])
        #expect(g263.trades.count == 2247 && g210.trades.count == 4731)
        #expect((g263.trades + g210.trades).allSatisfy { $0.stops.isEmpty && $0.targets.isEmpty })
        #expect(!(await g263.loadBars("BTCUSDT", .h4)).isEmpty)
        let ruleH = try #require(runs.first { $0.id == "E_ruleH_base_n25_H12_q95" })
        #expect(ruleH.trades.count == 2885)
        #expect(ruleH.trades.first { $0.exitReason == "delist_settlement" }?.exitTitle == "下架结算")
        // Most traded symbol first.
        let counts = ruleH.tradeCounts
        #expect(zip(ruleH.symbols, ruleH.symbols.dropFirst()).allSatisfy { (counts[$0] ?? 0) >= (counts[$1] ?? 0) })
        #expect(ruleH.timeframes("BTCUSDT") == [.m15, .h1, .h4, .d1])
        let bars = await ruleH.loadBars("BTCUSDT", .h1)
        #expect(bars.count > 30_000 && zip(bars, bars.dropFirst()).allSatisfy { $0.t < $1.t })
        #expect(ruleH.cachedBars("BTCUSDT", .h1)?.count == bars.count)
        #expect(!(await ruleH.loadSignals("BTCUSDT")).isEmpty)

        let ti7 = try #require(runs.first { $0.id == "C_ti7_10" })
        #expect(ti7.trades.count == 613)
        #expect(ti7.trades.filter { $0.exitPrice == nil }.count == 7)
        #expect(ti7.trades.allSatisfy { $0.signalsAtEntry.isEmpty })
        #expect(ti7.metrics.stepDays == 7)

        let lockboxF = try #require(runs.first { $0.id == "lockbox_v2_exam_F_listing" })
        #expect(lockboxF.trades.allSatisfy { $0.reportedPnlGross == nil && $0.reportedMfe == nil })
        #expect(lockboxF.metrics.overall.feeShare == nil)
    }

    @Test func viewerOpensTheRootFolderAheadOfTheSample() async throws {
        guard FileManager.default.fileExists(atPath: Self.realRoot.appending(path: "index.json").path()) else { return }
        let model = BacktestViewerModel(loadsSavedRuns: false)
        model.open(directory: Self.realRoot, remembers: false)
        #expect(model.loadError == nil)
        #expect(model.directoryRuns.count == 13 && model.sampleRuns.count == 3)
        #expect(model.runID == "g263_ema1h_vol10") // first in index.json
        #expect(model.runSections.map(\.title) == ["导出的回测", "内置样例"])
        #expect(model.runs.first?.id == model.runID && model.run.directory != nil)
        // Only the shown run has read its trades.
        let loadedIDs = model.directoryRuns.filter { $0.isLoaded }.map(\.id)
        #expect(loadedIDs == [model.runID])

        model.changeRun("E_ruleH_base_n25_H12_q95")
        #expect(model.timeframe == .h1)
        #expect(model.run.symbols.contains(model.symbol)) // kept from the previous run when traded here too
        #expect(model.isLoadingBars && model.bars.isEmpty)
        _ = await model.run.loadBars(model.symbol, model.timeframe)
        #expect(!model.bars.isEmpty && !model.isLoadingBars)
        #expect(model.chartTrades.allSatisfy { $0.hasPrices })

        // An unpriced trade stays listed but is never drawn.
        model.changeRun("C_ti7_10")
        let unpriced = try #require(model.run.trades.first { !$0.hasPrices })
        #expect(model.listedTrades.contains { $0.id == unpriced.id })
        model.focus(unpriced)
        #expect(!model.chartTrades.contains { $0.id == unpriced.id })
        #expect(model.timeframe != .m15)

        // Reopening one run folder replaces that run, keeping the others.
        model.open(directory: Self.realRoot.appending(path: "A_trend_lo", directoryHint: .isDirectory), remembers: false)
        #expect(model.directoryRuns.count == 13 && model.runID == "A_trend_lo")
    }
}
