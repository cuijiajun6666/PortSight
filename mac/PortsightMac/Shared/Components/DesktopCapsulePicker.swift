import SwiftUI
import PortSightKit

/// A native segmented control. The system draws it (Liquid Glass in the toolbar, the standard bezel in content),
/// so it follows light / dark mode and accent colour on its own. The name is kept for its many call sites.
struct DesktopCapsulePicker<Selection: Hashable>: View {
    let title: String
    let options: [Selection]
    @Binding var selection: Selection
    let label: (Selection) -> String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { option in
                Text(label(option)).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(title)
    }
}

/// A native pop-up menu for longer option lists.
struct DesktopCapsuleMenu<Selection: Hashable, Options: View>: View {
    let title: String
    let value: String
    @Binding var selection: Selection
    @ViewBuilder var options: Options

    var body: some View {
        Picker(title, selection: $selection) { options }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(title)
            .accessibilityValue(value)
    }
}
