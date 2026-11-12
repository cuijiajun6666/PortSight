//
//  PortSightNavigationHeader.swift
//  PortSight
//
//  The one place that styles the top of a page, following Photos (PhotosTB sample): a large bold title on
//  the leading side with a small line under it, over the soft scroll-edge blur, and the page's own buttons
//  on the trailing side. Pages call `.portSightHeader(...)`; the soft edge for every other scroll view is
//  set once at the app root with `.portSightScrollEdge()`.
//

import SwiftUI

extension View {
    /// Photos-style header: large leading title (a page switch when the page has a page menu) and a caption.
    func portSightHeader(_ title: String, caption: String? = nil) -> some View {
        modifier(PortSightHeaderModifier(title: title, caption: caption))
    }

    /// Soft, light scroll-edge blur under every navigation bar below this view.
    func portSightScrollEdge() -> some View {
        scrollEdgeEffectStyle(.soft, for: .top)
    }
}

private struct PortSightHeaderModifier: ViewModifier {
    let title: String
    let caption: String?

    func body(content: Content) -> some View {
        content
            .portSightScrollEdge()
            .toolbar {
                ToolbarItem(placement: .subtitle) {
                    PortSightHeader(title: title, caption: caption)
                }
            }
    }
}

/// Title and caption. When the environment carries a page menu (图库: 照片 / 文件), the title is that menu.
struct PortSightHeader: View {
    let title: String
    var caption: String?
    /// Passed in where the toolbar item does not see the page's environment.
    var menu: PageMenuModel?
    @Environment(\.pageMenu) private var environmentMenu

    private var pageMenu: PageMenuModel? { menu ?? environmentMenu }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let pageMenu {
                Menu {
                    Picker(pageMenu.name, selection: pageMenu.selection) {
                        ForEach(pageMenu.titles, id: \.self) { Text($0).tag($0) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        titleText(pageMenu.selection.wrappedValue)
                        Image(systemName: "chevron.down").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                }
                .accessibilityLabel(pageMenu.name + "：" + pageMenu.selection.wrappedValue)
            } else {
                titleText(title).accessibilityAddTraits(.isHeader)
            }
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 15)
    }

    private func titleText(_ text: String) -> some View {
        Text(text).font(.title.bold()).contentTransition(.interpolate).lineLimit(1)
    }
}
