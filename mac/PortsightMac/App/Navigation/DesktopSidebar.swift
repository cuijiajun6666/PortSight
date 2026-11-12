import SwiftUI
import PortSightKit

/// Transparent icon rail with a single sliding selection background.
struct DesktopSidebar: View {
    @Binding var selection: DesktopSection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let itemWidth: CGFloat = 44
    private let itemHeight: CGFloat = 36
    private let itemSpacing: CGFloat = 2

    private var selectedPage: DesktopSection { selection }
    private var selectionOffset: CGFloat {
        let index = DesktopSection.allCases.firstIndex(of: selectedPage) ?? 0
        return CGFloat(index) * (itemHeight + itemSpacing)
    }

    var body: some View {
        VStack(spacing: itemSpacing) {
            VStack(spacing: itemSpacing) {
                ForEach(DesktopSection.allCases) { page in
                    Button { selection = page } label: {
                        ZStack {
                            Image(systemName: page.icon)
                                .opacity(selectedPage == page ? 0 : 1)
                            Image(systemName: page.selectedIcon)
                                .opacity(selectedPage == page ? 1 : 0)
                        }
                            .font(.system(size: 18))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.primary)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selectedPage)
                            .frame(width: itemWidth, height: itemHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(page.title)
                    .accessibilityLabel(page.title)
                    .accessibilityIdentifier("nav_" + page.id)
                    .accessibilityValue(selectedPage == page ? "已选择" : "")
                    .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
                }
            }
            .background(alignment: .top) {
                // Keep one shape alive: changing pages moves it through every row in between.
                Color.clear
                    .frame(width: itemHeight, height: itemHeight)
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .offset(y: selectionOffset)
                    .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.24), value: selectedPage)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 56)
        .frame(maxHeight: .infinity)
    }
}
