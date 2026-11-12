import SwiftUI
import PortSightKit

/// One relay alert: severity glyph, title, source line and age. Unread rows carry a blue dot.
struct DesktopAlertRow: View {
    let alert: TerminalAlert
    var isRead = false
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: alert.severity.icon)
                .font(.system(size: compact ? 13 : 15))
                .foregroundStyle(DesktopStatus.color(alert.severity))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title).font(.system(size: 13, weight: isRead ? .regular : .semibold)).lineLimit(1)
                if !compact {
                    Text(alert.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    Label(alert.category.title, systemImage: alert.category.icon)
                    Text("·")
                    Text(alert.source)
                }
                .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) {
                Text(TerminalFormat.relative(alert.at)).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                if !isRead { DesktopStatusDot(color: DesktopTheme.blue, size: 6).accessibilityLabel("未读") }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A storage volume with a native capacity gauge.
struct DesktopVolumeRow: View {
    let volume: StorageVolume

    private var tint: Color {
        volume.usedFraction > 0.9 ? .red : volume.usedFraction > 0.75 ? DesktopTheme.orange : DesktopTheme.blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(volume.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).layoutPriority(1)
                Text(volume.role).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if volume.mounted {
                    Text(TerminalFormat.gigabytes(volume.freeGB) + " 可用").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Label("未挂载", systemImage: "eject").font(.system(size: 11)).foregroundStyle(DesktopTheme.orange)
                }
            }
            DesktopCapsuleBar(fraction: volume.mounted ? volume.usedFraction : 0, tint: tint)
                .accessibilityLabel("已用")
                .accessibilityValue(volume.mounted ? TerminalFormat.percent(volume.usedFraction, signed: false) : "未挂载")
            Text(volume.mounted ? TerminalFormat.gigabytes(volume.usedGB) + " / " + TerminalFormat.gigabytes(volume.totalGB) : "容量未知")
                .font(.system(size: 10)).foregroundStyle(.tertiary).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Mode capsule for a trading line (影子 / 模拟盘 / 实盘).
struct DesktopModePill: View {
    let mode: TradingMode
    var body: some View {
        DesktopPill(text: mode.title, color: mode == .live ? DesktopTheme.green : mode == .paper ? DesktopTheme.blue : .purple)
            .help(mode.detail)
    }
}

/// Compact summary of a trading line, used on 总览 and in the 交易 list.
struct DesktopLineSummary: View {
    let line: TradingLine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: line.icon).font(.system(size: 17)).foregroundStyle(.secondary)
                Text(line.title).font(.system(size: 15, weight: .semibold))
                // Forward seal: a shadow line shows no returns until the seal opens.
                if DesktopLineSeal.isSealed(line) {
                    Text("封存中").font(.system(size: 12)).foregroundStyle(.secondary)
                        .help("影子账本在前向封存期，收益 \(DesktopLineSeal.opensTitle) 开放")
                } else {
                    Text(TerminalFormat.percent(line.daily.returnPct))
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(DesktopTheme.pnlColor(line.daily.returnPct))
                        .contentTransition(.numericText(value: line.daily.returnPct))
                        .help("今日收益")
                }
                Spacer()
                DesktopModePill(mode: line.mode)
            }
            HStack(spacing: 6) {
                DesktopStatusDot(color: DesktopStatus.color(line.state))
                Text(line.lastResult).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("上线检验").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(line.checksPassed)/\(line.checksTotal)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                }
                ProgressView(value: line.readiness).progressViewStyle(.linear).tint(DesktopTheme.blue)
            }
            Text("上次运行 " + TerminalFormat.relative(line.lastRun)).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// One 需要处理 row: tinted symbol, title, detail and a chevron.
struct DesktopAttentionRow: View {
    let item: AttentionItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 15))
                .foregroundStyle(item.tone == .critical ? Color.red : DesktopTheme.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(item.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 今日最佳 / 今日最差: label, the holding's symbol mark and ticker, and today's move in profit / loss colour.
struct DesktopMoverStat: View {
    let label: String
    let holding: DemoHolding

    var body: some View {
        let change = holding.dayChange
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                DesktopSymbol(symbol: holding.symbol, crypto: SymbolLogoStore.isCrypto(holding.symbol, kind: holding.kind), size: 22)
                Text(holding.symbol).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Text(TerminalFormat.percent(change))
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(DesktopTheme.pnlColor(change))
                    .contentTransition(.numericText(value: change))
            }
            Text(holding.name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Plain row button with a soft rounded highlight on hover and press.
struct DesktopHoverRowStyle: ButtonStyle {
    var inset: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        HoverRow(configuration: configuration, inset: inset)
    }

    private struct HoverRow: View {
        let configuration: Configuration
        let inset: CGFloat
        @State private var hovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, inset)
                .padding(.vertical, inset * 0.75)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.09 : hovered ? 0.05 : 0))
                }
                .padding(.horizontal, -inset)
                .onHover { hovered = $0 }
                .animation(.smooth(duration: 0.15), value: hovered)
        }
    }
}

/// A fully rounded usage bar (capsule track and fill), used for disk capacity.
struct DesktopCapsuleBar: View {
    let fraction: Double
    var tint: Color = DesktopTheme.blue
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(tint)
                    .frame(width: fraction > 0 ? max(height, proxy.size.width * min(fraction, 1)) : 0)
            }
        }
        .frame(height: height)
        .animation(.smooth, value: fraction)
    }
}
