import SwiftUI
import AppKit
import PortSightKit

/// A stock, ETF or coin's real icon in the Mac's rounded square (SymbolLogoStore: logo.dev, downloaded once and kept
/// on this device), or its first letter on a soft tint while the icon loads or when logo.dev has none.
struct DesktopSymbol: View {
    let symbol: String
    /// nil: decided from the symbol (well-known coins and USDT pairs are coins). Pass the holding's kind when known.
    var crypto: Bool? = nil
    var size: CGFloat = 37

    var body: some View {
        let isCrypto = crypto ?? SymbolLogoStore.isCrypto(symbol)
        let store = SymbolLogoStore.shared
        let data = store.image(symbol, crypto: isCrypto)
        let shape = RoundedRectangle(cornerRadius: size * 0.3)
        ZStack {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                let tint = DesktopTheme.symbolColor(symbol)
                shape.fill(tint.opacity(0.08))
                Text(Self.letter(symbol))
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .animation(.smooth(duration: 0.25), value: data != nil)
        .task(id: symbol + (isCrypto ? "|crypto" : "|stock")) { await store.load(symbol, crypto: isCrypto) }
        .accessibilityHidden(true)
    }

    /// "US.AAPL" → "A", "BTC-USDT" → "B".
    private static func letter(_ symbol: String) -> String {
        var ticker = symbol
        for prefix in ["US.", "HK.", "SH.", "SZ."] where ticker.uppercased().hasPrefix(prefix) {
            ticker.removeFirst(prefix.count)
        }
        return String(ticker.prefix(1)).uppercased()
    }
}
