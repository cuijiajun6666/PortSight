import SwiftUI
import PortSightKit

/// A page laid out directly on the content surface: no cards, hierarchy comes from type, spacing and hairlines.
struct DesktopFullPage<Content: View>: View {
    var maxWidth: CGFloat = 1_180
    var spacing: CGFloat = 34
    @ViewBuilder var content: Content

    var body: some View {
        DesktopPageScrollView {
            VStack(alignment: .leading, spacing: spacing) { content }
                .frame(maxWidth: maxWidth, alignment: .leading)
                .padding(.horizontal, 36)
                .padding(.top, 30)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Large page header: an eyebrow, the key figure or statement, and a supporting line.
struct DesktopPageHeader<Accessory: View>: View {
    let eyebrow: String
    let title: String
    var detail: String? = nil
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Text(title).font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit().contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.7)
                if let detail { Text(detail).font(.system(size: 13)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            accessory
        }
    }
}

extension DesktopPageHeader where Accessory == EmptyView {
    init(eyebrow: String, title: String, detail: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, detail: detail) { EmptyView() }
    }
}

/// A titled region of a full page, separated from the previous one by a hairline.
struct DesktopPageSection<Content: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var showsDivider = true
    var spacing: CGFloat = 18
    @ViewBuilder var content: Content
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if showsDivider { Divider().opacity(0.6) }
            HStack(alignment: .firstTextBaseline) {
                DesktopSectionTitle(title: title, subtitle: subtitle)
                Spacer()
                trailing
            }
            content
        }
    }
}

extension DesktopPageSection where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, showsDivider: Bool = true, spacing: CGFloat = 18,
         @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, showsDivider: showsDivider, spacing: spacing, content: content) { EmptyView() }
    }
}

/// A figure with its label, used in rows of key numbers.
struct DesktopStat: View {
    let label: String
    let value: Text
    var detail: String? = nil
    var tint: Color = .primary

    init(label: String, value: String, detail: String? = nil, tint: Color = .primary) {
        self.init(label: label, value: Text(value), detail: detail, tint: tint)
    }

    /// A value made of differently coloured parts (each part's own colour wins over `tint`).
    init(label: String, value: Text, detail: String? = nil, tint: Color = .primary) {
        self.label = label
        self.value = value
        self.detail = detail
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            value.font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            if let detail {
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Status colours shared by the terminal pages.
enum DesktopStatus {
    /// CPU / GPU temperature: normal as plain text, 85–95 °C yellow, over 95 °C red.
    static func temperature(_ level: TemperatureLevel?) -> Color {
        switch level {
        case .warm: DesktopTheme.yellow
        case .hot: .red
        case .normal, nil: .primary
        }
    }

    /// "88.4°C / 96.2°C", each reading in its own colour ("—" when macmon gave nothing).
    static func temperatures(_ thermal: HostThermal?) -> Text {
        let cpu = Text(HostThermal.text(thermal?.cpu_temp_c)).foregroundStyle(temperature(thermal?.cpuLevel))
        let gpu = Text(HostThermal.text(thermal?.gpu_temp_c)).foregroundStyle(temperature(thermal?.gpuLevel))
        return Text("\(cpu) / \(gpu)")
    }

    /// What is wrong with the temperatures, in words (so it never rests on colour alone): throttling, then which
    /// reading is warm or hot. nil when nothing is.
    static func thermalProblem(_ thermal: HostThermal?) -> String? {
        guard let thermal else { return nil }
        var parts: [String] = []
        if let limit = thermal.cpu_speed_limit, limit < 100 {
            parts.append("降频至 \(limit)%")
        } else if thermal.overheated {
            parts.append("已过热降频")
        }
        parts += thermal.warmReadings.map { $0.name + " " + $0.level.word }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The line under the temperatures on the server page.
    static func thermalNote(_ thermal: HostThermal?) -> String {
        guard let thermal else { return "—" }
        if let problem = thermalProblem(thermal) { return problem }
        if !(thermal.performance_warning?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) { return "有性能告警" }
        if thermal.cpu_temp_c == nil && thermal.gpu_temp_c == nil { return "暂无温度读数" }
        return thermal.available == false ? "温度正常" : "温度正常 · 无降频"
    }

    static func color(_ state: TerminalState) -> Color {
        switch state {
        case .ok: DesktopTheme.green
        case .warning: DesktopTheme.orange
        case .critical: .red
        case .idle, .pending: .secondary
        }
    }

    static func color(_ severity: AlertSeverity) -> Color {
        switch severity {
        case .critical: .red
        case .warning: DesktopTheme.orange
        case .info: DesktopTheme.blue
        }
    }

    /// Relay heartbeat / job states (ok, stale, critical, missing, not_installed, running, idle ...).
    static func color(relay state: String?) -> Color {
        switch state {
        case "ok", "running", "fresh", "normal": DesktopTheme.green
        case "stale", "warning", "error", "failed": DesktopTheme.orange
        case "critical", "missing", "down": .red
        default: .secondary
        }
    }

    static func title(relay state: String?) -> String {
        switch state {
        case "ok": "正常"
        case "stale": "超时"
        case "critical": "严重超时"
        case "missing": "没有心跳"
        case "not_installed": "未安装"
        case "stopped": "已停止"
        case "running": "运行中"
        case "idle": "空闲"
        case "error": "出错"
        case "warning": "注意"
        default: state ?? "—"
        }
    }
}

struct DesktopStatusDot: View {
    let color: Color
    var size: CGFloat = 7
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

/// "尚未接入" marker for sections whose data source is not connected yet (plan §0.1).
struct DesktopPendingLabel: View {
    var text = "尚未接入"
    var body: some View {
        Label(text, systemImage: "circle.dashed")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }
}
