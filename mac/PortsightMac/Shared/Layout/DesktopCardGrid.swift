import SwiftUI
import PortSightKit

/// Heights include the gutters: large = medium + gap + small.
enum DesktopCardSize: Int {
    case small = 1
    case medium = 2
    case large = 3

    var height: CGFloat {
        CGFloat(rawValue) * DesktopCardGrid.rowHeight
            + CGFloat(rawValue - 1) * DesktopCardGrid.spacing
    }
}

enum DesktopCardGrid {
    static let rowHeight: CGFloat = 164
    static let spacing: CGFloat = 12
    static let wideBreakpoint: CGFloat = 1_000

    /// Twelve equal columns when wide, six when narrow.
    static func width(span: Int, columns: Int, available: CGFloat) -> CGFloat {
        let unit = (available - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        return unit * CGFloat(span) + CGFloat(span - 1) * spacing
    }
}
