import SwiftUI
import PortSightKit

/// A section's tabs, shown in the toolbar row beside the account scope picker.
/// Each tab group uses the shared capsule control.
struct DesktopSectionTabs: View {
    let groups: [[DesktopTab]]
    @Binding var selection: DesktopTab

    var body: some View {
        HStack(spacing: 10) {
            ForEach(groups.indices, id: \.self) { index in
                let group = groups[index]
                DesktopCapsulePicker(title: "页面", options: group.map { Optional($0) }, selection: binding(for: group)) { $0?.title ?? "" }
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("section_tabs_\(index)")
            }
        }
    }

    /// A group shows no selected segment while another group's tab is active.
    private func binding(for group: [DesktopTab]) -> Binding<DesktopTab?> {
        Binding(
            get: { group.contains(selection) ? selection : nil },
            set: { if let tab = $0 { selection = tab } }
        )
    }
}
