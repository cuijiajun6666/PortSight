import SwiftUI
import PortSightKit

struct DesktopAllocationCard: View {
    let items: [AllocationItem]
    let scope: PortfolioScope
    let total: Double
    let cash: Double
    var openPositions: () -> Void

    var body: some View {
        DesktopCard(padding: 20, size: .medium) {
            DesktopAllocationContent(items: items, scope: scope, total: total, cash: cash,
                                     openPositions: openPositions)
        }
        .accessibilityIdentifier("allocation_card")
    }
}
