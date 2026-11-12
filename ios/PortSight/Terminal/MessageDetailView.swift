//
//  MessageDetailView.swift
//  PortSight
//
//  The detail page for any message (notice or server alert). The severity sets the page: a soft gradient in
//  its colour (like 资产 → 分析), its large symbol glowing in the top-left corner of the background, then the
//  title and description large enough to read at a glance, and the facts in a card below.
//

import SwiftUI
import PortSightKit

struct MessageDetailLayout: View {
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

    /// Where a notice leads (its RelayLink): 去重新授权, 查看日报, 查看理由卡 …
    struct LinkAction {
        let title: String
        let icon: String
        let perform: () -> Void
    }

    let severity: AlertSeverity
    let category: String
    let categoryIcon: String
    let title: String
    let detail: String
    /// Short facts on the severity line: source, owner, time.
    var meta: [String] = []
    var facts: [Fact] = []
    /// Earlier occurrences of the same alert (time → severity), listed under their own heading.
    var history: [Fact] = []
    var historyTitle = "同类告警"
    var link: LinkAction?
    var action: Action?
    var footnote: String?

    @State private var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { TerminalStyle.color(severity) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // The large glowing symbol, sitting on the gradient behind the headline. It lives in the
                // scroll content so it lands in the same place pushed or in a sheet.
                Image(systemName: severity.icon)
                    .font(.system(size: 224, weight: .semibold))
                    .foregroundStyle(tint.gradient)
                    .shadow(color: tint.opacity(glow ? 0.75 : 0.45), radius: glow ? 48 : 32)
                    .opacity(0.9)
                    // Pushed into the top-left corner, a little cut off by the screen edges.
                    .offset(x: -64, y: -84)
                    .frame(height: 150, alignment: .topLeading)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(severity.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(tint, in: Capsule())
                        Label(category, systemImage: categoryIcon)
                        ForEach(meta, id: \.self) { item in
                            Text("·")
                            Text(item)
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    Text(title)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !facts.isEmpty {
                VStack(spacing: 0) {
                    // By position: a notice may repeat a label.
                    ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                        if index > 0 { Divider().padding(.leading, 16) }
                        LabeledContent(fact.label, value: fact.value)
                            .padding(.horizontal, 16).padding(.vertical, 13)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(historyTitle).font(.headline).padding(.leading, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(history.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Divider().padding(.leading, 16) }
                                LabeledContent(item.label, value: item.value)
                                    .monospacedDigit()
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                            }
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }

                if let link {
                    // The main button when there is nothing to confirm; beside 确认已查看 it steps back.
                    linkButton(link, prominent: action == nil)
                }

                if let action {
                    Button {
                        action.perform()
                    } label: {
                        Label(action.isDone ? action.doneTitle : action.title,
                              systemImage: action.isDone ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(tint)
                    .disabled(action.isDone)
                    .sensoryFeedback(.success, trigger: action.isDone)
                }

                if let footnote {
                    Text(footnote).font(.footnote).foregroundStyle(.secondary)
                }
            }
            // Always the full width: without a full-width button (server alerts have none) the column was only as wide
            // as its text, so the scroll view shrank to it and the page sat inset, its edges cut.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .topLeading) { backdrop }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { glow = true }
        }
    }

    @ViewBuilder private func linkButton(_ link: LinkAction, prominent: Bool) -> some View {
        let button = Button(action: link.perform) {
            Label(link.title, systemImage: link.icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        if prominent {
            button.buttonStyle(.glassProminent).tint(tint)
        } else {
            button.buttonStyle(.glass)
        }
    }

    /// Gradient in the severity colour behind everything.
    private var backdrop: some View {
        ZStack(alignment: .topLeading) {
            Color(.systemGroupedBackground)
            LinearGradient(colors: [tint.opacity(0.55), tint.opacity(0.22), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 520)
                .blur(radius: 30)
                .padding(.horizontal, -50)
                .padding(.top, -30)
        }
        .ignoresSafeArea()
    }
}
