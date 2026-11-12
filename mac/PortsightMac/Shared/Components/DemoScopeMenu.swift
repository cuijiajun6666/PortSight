import SwiftUI
import PortSightKit
struct DemoScopeMenu: View {
    @EnvironmentObject private var demo: PortfolioDemo
    var body: some View {
        Menu {
            Picker("资产范围", selection: $demo.scope) {
                ForEach(PortfolioScope.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            HStack(spacing: 5) {
                Text(demo.scope.rawValue).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
        }.buttonStyle(.glass).buttonBorderShape(.capsule).accessibilityLabel("资产范围：" + demo.scope.rawValue)
    }
}
