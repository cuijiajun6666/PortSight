//
//  PortSightBackdrop.swift
//  PortSight
//
//  The backdrop shared by every tab but 更多: an orange and a blue glow across the top. Dark mode: seen through a thin
//  material (a soft grey rather than black). Light mode: on the system's grouped grey, with white cards. Lists and
//  forms hide their own background to show it.
//

import SwiftUI

struct PortSightBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            // Light mode: the system's grouped grey underneath (cards are white on it, like Settings).
            if !dark { Color(.systemGroupedBackground).ignoresSafeArea() }
            VStack {
                HStack(spacing: 0) {
                    Circle()
                        .fill(LinearGradient(colors: [Color.orange.opacity(0.4), Color.orange.opacity(0.2), .clear],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .offset(x: 60)
                    Circle()
                        .fill(LinearGradient(colors: [Color.blue.opacity(0.4), Color.blue.opacity(0.2), .clear],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .blur(radius: 40)
                .offset(y: -150)
                .ignoresSafeArea()
                .padding(.horizontal, -100)
                // A softer glow on the light grey.
                .opacity(dark ? 1 : 0.55)
                Spacer()
            }
            // Dark mode: the 资产 · 概览 page's thin material over the glow (unchanged).
            if dark {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

extension View {
    /// The shared backdrop behind this page (a ScrollView, List or Form); a list's own background is hidden so the
    /// glow shows through.
    func portSightBackdrop() -> some View {
        scrollContentBackground(.hidden)
            .background { PortSightBackdrop().ignoresSafeArea() }
    }
}

/// The card fill, by appearance (switches with light / dark mode): in dark mode the 资产 · 概览 cards' material
/// (DemoCard, e.g. 资金由谁管理), which stands out from the dark backdrop; in light mode the system's grouped card
/// colour (white) on the grouped grey backdrop, like Settings.
struct PortSightCardFill: View {
    var cornerRadius: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if colorScheme == .dark {
            shape.fill(.regularMaterial)
        } else {
            // White on the grouped grey backdrop: the system's grouped card colour.
            shape.fill(Color(.secondarySystemGroupedBackground))
        }
    }
}

extension View {
    /// A List row (or a whole Section / ForEach of rows) on the backdrop: filled like the 资产 cards. The inset-grouped
    /// list still rounds each section's corners.
    func portSightCardRow() -> some View {
        listRowBackground(PortSightCardFill())
    }

    /// A custom card (not a List row): the shared card fill (by appearance) and the 资产 cards' corner radius.
    func portSightCard(cornerRadius: CGFloat = 30) -> some View {
        background { PortSightCardFill(cornerRadius: cornerRadius) }
    }
}

/// A List whose rows are filled like the 资产 cards (PortSightCardFill), so on the backdrop every card's size shows.
/// Rows that set their own background (a clear hero row, a picker) keep it: the innermost listRowBackground wins.
struct PortSightList<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        List {
            Group { content }
                .portSightCardRow()
        }
    }
}
