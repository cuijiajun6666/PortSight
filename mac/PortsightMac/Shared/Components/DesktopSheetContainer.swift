import SwiftUI
import PortSightKit
/// `showsTitleBar: false` drops the title bar (every 通知详情 / 告警详情): the page's own colour runs to the top edge, and 完成
/// sits at the bottom right.
struct DesktopSheetContainer<Content: View>: View {
    let title: String
    var width: CGFloat = 850
    var height: CGFloat = 720
    var showsTitleBar = true
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if showsTitleBar {
                NavigationStack {
                    // Glass buttons for the page only: the toolbar's 完成 keeps the system sheet button.
                    content
                        .buttonStyle(.glass)
                        .navigationTitle(title)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { doneButton }
                        }
                }
            } else {
                // 完成 gets its own row under the page: floated over a ScrollView, the scroll view took its clicks.
                VStack(spacing: 0) {
                    content
                        .buttonStyle(.glass)
                        .frame(maxHeight: .infinity)
                    HStack {
                        Spacer()
                        doneButton.buttonStyle(.glass).controlSize(.large)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
        }
        .frame(width: width, height: height)
        .presentationSizing(.fitted)
    }

    private var doneButton: some View {
        Button("完成") { dismiss() }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("sheet_done")
    }
}

