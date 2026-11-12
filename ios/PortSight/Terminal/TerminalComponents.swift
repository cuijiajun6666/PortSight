//
//  TerminalComponents.swift
//  PortSight
//
//  Small building blocks shared by the terminal tabs (总览, 交易, 更多). Data comes from PortSightKit's demo
//  fixtures until the Mac mini relay is connected.
//

import SwiftUI
import PortSightKit

enum TerminalStyle {
    static func color(_ state: TerminalState) -> Color {
        switch state {
        case .ok: .green
        case .warning: .orange
        case .critical: .red
        case .idle, .pending: .secondary
        }
    }

    /// The kit's one severity mapping (red / orange / blue).
    static func color(_ severity: AlertSeverity) -> Color { severity.tint }

    static func color(mode: TradingMode) -> Color {
        switch mode {
        case .shadow: .purple
        case .paper: .blue
        case .live: .green
        }
    }

    static func color(relay state: String?) -> Color {
        switch state {
        case "ok", "running", "normal": .green
        case "stale", "warning", "error": .orange
        case "critical", "missing", "down": .red
        default: .secondary
        }
    }

    static func pnl(_ value: Double) -> Color { value >= 0 ? .green : .red }
}

struct TerminalModeBadge: View {
    let mode: TradingMode
    var body: some View {
        Text(mode.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(TerminalStyle.color(mode: mode))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(TerminalStyle.color(mode: mode).opacity(0.12), in: Capsule())
    }
}

struct TerminalPendingBadge: View {
    var body: some View {
        Label("尚未接入", systemImage: "circle.dashed")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

/// One relay alert row: severity glyph, title, category and age.
struct TerminalAlertRow: View {
    let alert: TerminalAlert
    var isRead = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: alert.severity.icon)
                .foregroundStyle(TerminalStyle.color(alert.severity))
                .font(.body)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title).font(.subheadline.weight(isRead ? .regular : .semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    Label(alert.category.title, systemImage: alert.category.icon)
                    Text("·")
                    Text(TerminalFormat.relative(alert.at))
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !isRead { Circle().fill(.blue).frame(width: 8, height: 8).padding(.top, 6).accessibilityLabel("未读") }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Compact line summary used on 总览 and in the 交易 list.
struct TerminalLineRow: View {
    let line: TradingLine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: line.icon).foregroundStyle(.secondary).frame(width: 22)
                Text(line.title).font(.headline)
                Spacer()
                TerminalModeBadge(mode: line.mode)
            }
            HStack(spacing: 6) {
                Circle().fill(TerminalStyle.color(line.state)).frame(width: 7, height: 7)
                Text(line.lastResult).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text(TerminalFormat.relative(line.lastRun)).font(.caption).foregroundStyle(.tertiary)
            }
            HStack(spacing: 10) {
                ProgressView(value: line.readiness).tint(.blue)
                Text("上线检验 \(line.checksPassed)/\(line.checksTotal)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}

/// A storage volume with a native capacity gauge.
struct TerminalVolumeRow: View {
    let volume: StorageVolume

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(volume.title).font(.subheadline.weight(.semibold))
                Text(volume.role).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if volume.mounted {
                    Text(TerminalFormat.gigabytes(volume.freeGB) + " 可用").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Label("未挂载", systemImage: "eject").font(.caption).foregroundStyle(.orange)
                }
            }
            Gauge(value: volume.mounted ? volume.usedFraction : 0) { EmptyView() }
                .gaugeStyle(.linearCapacity)
                .tint(volume.usedFraction > 0.9 ? .red : volume.usedFraction > 0.75 ? .orange : .blue)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Large figure for a list's opening section, shown on the grouped background.
struct TerminalHero<Accessory: View>: View {
    let eyebrow: String
    let value: String
    let detail: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit().contentTransition(.numericText()).minimumScaleFactor(0.6).lineLimit(1)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
            accessory.padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 总览 and the 交易 pages: the list starts right under the toolbar, its sections sit close together, and it lies on
/// the 资产 page's backdrop (orange and blue glow under a thin material); rows and cards keep their own fill.
extension View {
    func terminalPageList() -> some View {
        listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .contentMargins(.top, 0, for: .scrollContent)
            .portSightBackdrop()
    }

    /// A page's first row (title line, big figure, menus): flush with the page title, like 总览's total. The row's
    /// rounded corner clips whatever sits in it, so the top padding keeps the first line clear of that corner.
    func terminalHeroRow() -> some View {
        padding(.top, TerminalHeroRow.top)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: TerminalHeroRow.bottom, trailing: 0))
    }
}

enum TerminalHeroRow {
    /// Enough for a subheadline line starting at the row's left edge to miss the corner.
    static let top: CGFloat = 18
    /// Same for the menus' glass capsules at the bottom-left corner.
    static let bottom: CGFloat = 12
}

extension TerminalHero where Accessory == EmptyView {
    init(eyebrow: String, value: String, detail: String) {
        self.init(eyebrow: eyebrow, value: value, detail: detail) { EmptyView() }
    }
}

func terminalMoney(_ value: Double) -> String {
    value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")).precision(.fractionLength(2)))
}

func terminalSignedMoney(_ value: Double) -> String { (value >= 0 ? "+" : "−") + terminalMoney(abs(value)) }

/// 累计 and 今日 under a total, in profit / loss colours (总览 and 资产 share it): real for the IBKR account once paired,
/// built in for the quant account. 「—」 only for a percentage whose base is 0.
struct PnLSummary: View {
    @EnvironmentObject private var demo: PortfolioDemo

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !demo.isLive {
                line("累计", terminalSignedMoney(demo.pnl) + " · " + TerminalFormat.percent(demo.pnlFraction),
                     value: demo.pnl)
                line("今日", terminalSignedMoney(demo.dayPnL) + " · " + TerminalFormat.percent(demo.dayFraction), value: demo.dayPnL)
            } else {
                let principal = demo.principal, previous = demo.total - demo.dayPnL
                line("累计", terminalSignedMoney(demo.pnl) + " · "
                     + (principal > 0 ? TerminalFormat.percent(demo.pnl / principal) : missingFigure), value: demo.pnl)
                line("今日", terminalSignedMoney(demo.dayPnL) + " · "
                     + (previous > 0 ? TerminalFormat.percent(demo.dayPnL / previous) : missingFigure), value: demo.dayPnL)
            }
        }
        .font(.subheadline)
        .animation(.smooth, value: demo.scope)
    }

    private func line(_ label: String, _ text: String, value: Double) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(.secondary)
            Text(text).fontWeight(.semibold).foregroundStyle(TerminalStyle.pnl(value)).monospacedDigit()
                .contentTransition(.numericText(value: value))
        }
    }
}
