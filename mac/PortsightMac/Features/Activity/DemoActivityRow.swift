import SwiftUI
import Charts
import PortSightKit
struct DemoActivityRow: View {
    let item: DemoActivity
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.icon).frame(width: 32, height: 32).background(.primary.opacity(0.05), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.medium))
                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                Text(item.time + " · " + (item.owner == .all ? "内部划转" : item.owner.rawValue)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 5)
            if let amount = item.amount { Text(demoMoney(amount)).font(.subheadline).monospacedDigit() }
        }.padding(.vertical, 4)
    }
}
