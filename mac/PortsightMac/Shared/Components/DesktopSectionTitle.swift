import SwiftUI
import PortSightKit
struct DesktopSectionTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 16, weight: .semibold))
            if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }
}

