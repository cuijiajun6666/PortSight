//
//  DesktopSymbolLogo.swift
//  PortsightMac
//
//  A stock, ETF or coin icon (SymbolLogoStore: logo.dev, downloaded once and kept), or the letter placeholder while it
//  loads or when there is none.
//

import SwiftUI
import AppKit
import PortSightKit

struct DesktopSymbolLogo: View {
    let symbol: String
    /// nil: decided from the symbol (well-known coins and USDT pairs are coins).
    var crypto: Bool? = nil
    var size: CGFloat = 28

    var body: some View {
        let isCrypto = crypto ?? SymbolLogoStore.isCrypto(symbol)
        let store = SymbolLogoStore.shared
        ZStack {
            if let data = store.image(symbol, crypto: isCrypto), let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if !isCrypto && SymbolLogoStore.isCurrency(symbol) {
                // A currency (AUD.USD, USD): an exchange symbol, not a company logo.
                ZStack {
                    Color(nsColor: .systemGray)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(.white)
                }
            } else {
                DesktopSymbolLetter(symbol: symbol)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .animation(.smooth(duration: 0.25), value: store.image(symbol, crypto: isCrypto) != nil)
        .task(id: symbol) { await store.load(symbol, crypto: isCrypto) }
        .accessibilityHidden(true)
    }
}

/// The first letter on a colour taken from the symbol.
struct DesktopSymbolLetter: View {
    let symbol: String

    var body: some View {
        let ticker = symbol.replacingOccurrences(of: "US.", with: "")
        let hue = Double(ticker.unicodeScalars.reduce(0) { $0 + Int($1.value) * 37 } % 360) / 360
        GeometryReader { proxy in
            ZStack {
                Color(hue: hue, saturation: 0.45, brightness: 0.75)
                Text(String(ticker.prefix(1)))
                    .font(.system(size: proxy.size.width * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}
