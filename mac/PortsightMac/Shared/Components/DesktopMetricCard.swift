import SwiftUI
import PortSightKit
struct DesktopMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    var tint: Color = DesktopTheme.blue
    var body: some View {
        DesktopCard(padding: 20, size: .small) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint)
                }
                Text(value).font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit().contentTransition(.numericText()).minimumScaleFactor(0.7).lineLimit(1)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
