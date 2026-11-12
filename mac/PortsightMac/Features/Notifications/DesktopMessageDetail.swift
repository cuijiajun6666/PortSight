import SwiftUI
import PortSightKit

/// Shared layout for the bell's detail sheets, matching the iOS message page: a soft gradient in the severity
/// colour across the top, the severity's large symbol glowing in the top-left corner (a little cut off by the
/// sheet edge), a meta line, the title and description in large type, then the facts and the action.
struct DesktopMessageDetail: View {
    struct Fact: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    struct Action {
        let title: String
        let doneTitle: String
        let isDone: Bool
        let perform: () -> Void
    }

    /// Leads to the page the message is about (a notice's link: 去重新授权, 查看日报 …).
    struct Link {
        let title: String
        let icon: String
        let perform: () -> Void
    }

    let severity: AlertSeverity
    let category: String
    var categoryIcon: String = "bell"
    let title: String
    let message: String
    /// Short items after the category on the severity line: owner or source, then time.
    var meta: [String] = []
    var facts: [Fact] = []
    /// Earlier occurrences of the same alert (time → severity), under their own heading.
    var history: [Fact] = []
    var historyTitle = "同类告警"
    var action: Action? = nil
    var link: Link? = nil
    var note: String? = nil

    @State private var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { DesktopStatus.color(severity) }
    private var glowing: Bool { glow && !reduceMotion }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Lives in the scroll content so it sits behind the headline and scrolls with it.
                Image(systemName: severity.icon)
                    .font(.system(size: 160, weight: .semibold))
                    .foregroundStyle(tint.gradient)
                    .shadow(color: tint.opacity(glowing ? 0.75 : 0.45), radius: glowing ? 36 : 24)
                    .opacity(0.9)
                    // Pushed into the top-left corner, a little cut off by the sheet edges.
                    .offset(x: -54, y: -52)
                    // Room under the symbol, so the headline starts below it (the warning triangle is the tallest).
                    .frame(height: 136, alignment: .topLeading)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 10) {
                    metaLine
                    Text(title)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Text(message)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if !facts.isEmpty { card(facts) }

                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(historyTitle).font(.headline).padding(.leading, 4)
                        card(history).monospacedDigit()
                    }
                }

                if let action {
                    Button(action: action.perform) {
                        Label(action.isDone ? action.doneTitle : action.title,
                              systemImage: action.isDone ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(tint)
                    .controlSize(.large)
                    .disabled(action.isDone)
                    .accessibilityIdentifier("message_detail_action")
                }

                if let link {
                    Button(action: link.perform) {
                        Label(link.title, systemImage: link.icon)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .accessibilityIdentifier("message_detail_link")
                }

                if let note {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(alignment: .top) { backdrop }
        .accessibilityIdentifier("message_detail")
        .onAppear { startGlow() }
        .onChange(of: reduceMotion) { startGlow() }
    }

    /// "严重 · 类别 · 归属/来源 · 时间", with the severity as a white-on-tint capsule.
    private var metaLine: some View {
        HStack(spacing: 8) {
            Text(severity.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(tint, in: Capsule())
            Label(category, systemImage: categoryIcon)
            ForEach(Array(meta.enumerated()), id: \.offset) { _, item in
                Text("·")
                Text(item)
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func card(_ facts: [Fact]) -> some View {
        VStack(spacing: 0) {
            // By position: a notice may repeat a label.
            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                if index > 0 { Divider().padding(.leading, 14) }
                HStack {
                    Text(fact.label).foregroundStyle(.secondary)
                    Spacer(minLength: 16)
                    Text(fact.value).multilineTextAlignment(.trailing).textSelection(.enabled)
                }
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 11)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Gradient in the severity colour across the upper part of the sheet.
    private var backdrop: some View {
        LinearGradient(colors: [tint.opacity(0.5), tint.opacity(0.2), .clear],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: 360)
            .blur(radius: 30)
            .padding(.horizontal, -50)
            .padding(.top, -30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    /// A slow pulse on the symbol's glow; none under Reduce Motion.
    private func startGlow() {
        if reduceMotion {
            glow = false
            return
        }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { glow = true }
    }
}
