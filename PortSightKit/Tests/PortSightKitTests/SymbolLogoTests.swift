import Foundation
import Testing
@testable import PortSightKit

@MainActor
struct SymbolLogoTests {
    @Test func symbolsBecomeLogoURLs() throws {
        #expect(SymbolLogoStore.key("US.aapl", crypto: false) == "stock_AAPL")
        #expect(SymbolLogoStore.key("BTC-USDT", crypto: true) == "crypto_BTC")
        #expect(SymbolLogoStore.key("AUD.USD", crypto: false) == nil && SymbolLogoStore.key(" ", crypto: false) == nil)
        let stock = try #require(SymbolLogoStore.url("NVDA", crypto: false))
        #expect(stock.host == "img.logo.dev" && stock.path == "/ticker/NVDA" && stock.query?.contains("fallback=404") == true)
        #expect(SymbolLogoStore.url("ETH", crypto: true)?.path == "/crypto/eth")
        #expect(SymbolLogoStore.isLogoRequest(URLRequest(url: stock)))
        #expect(!SymbolLogoStore.isLogoRequest(URLRequest(url: URL(string: "https://example.com/x.png")!)))
    }

    @Test func iconsAreFetchedOnceAndKept() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("logos-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        // A 1×1 PNG.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
        var calls = 0
        let store = SymbolLogoStore(directory: directory) { url in
            calls += 1
            return url.path.hasSuffix("NOPE") ? (Data(), 404) : (png, 200)
        }
        await store.load("AAPL", crypto: false)
        await store.load("AAPL", crypto: false)
        #expect(calls == 1 && store.image("US.AAPL", crypto: false) == png)
        // Unknown to logo.dev: no icon, and not asked again within the hour.
        await store.load("NOPE", crypto: false)
        await store.load("NOPE", crypto: false)
        #expect(calls == 2 && store.image("NOPE", crypto: false) == nil)
        // A pair is never asked for.
        await store.load("AUD.USD", crypto: false)
        #expect(calls == 2)
        // The next launch has it at once.
        var later = 0
        let again = SymbolLogoStore(directory: directory) { _ in later += 1; return (Data(), 500) }
        #expect(again.image("AAPL", crypto: false) == png)
        // …and does not ask again for what logo.dev has no icon for.
        await again.load("NOPE", crypto: false)
        await again.load("AAPL", crypto: false)
        #expect(later == 0)
    }

    @Test func iconsFollowTheAssets() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("logos-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
        var asked: [String] = []
        let store = SymbolLogoStore(directory: directory) { url in
            asked.append(url.path)
            return (png, 200)
        }
        await store.sync([("AAPL", false), ("BTC", true)])
        #expect(asked == ["/crypto/btc", "/ticker/AAPL"])
        // A new asset is added, a sold one removed; the one still held is not downloaded again.
        await store.sync([("AAPL", false), ("NVDA", false)])
        #expect(asked.count == 3 && asked.last == "/ticker/NVDA")
        #expect(store.image("BTC", crypto: true) == nil && store.image("NVDA", crypto: false) == png)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("crypto_BTC.png").path))
        // Nothing known (e.g. before anything is read): the icons stay.
        await store.sync([])
        #expect(store.image("AAPL", crypto: false) == png)
    }
}
