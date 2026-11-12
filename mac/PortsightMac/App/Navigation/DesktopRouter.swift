import SwiftUI
import AppKit
import Combine
import PortSightKit

/// A request from outside the main window (the menu bar) to show a section or the bell panel.
/// It waits here until a window's ContentView takes it, so it also works when that window is opened by the request.
@MainActor
final class DesktopRouter: ObservableObject {
    enum Route: Equatable {
        case section(DesktopSection)
        case notifications
        /// A clicked relay push: the bell panel, with that event's page on top.
        case event(PushEventRef)
    }

    @Published var pending: Route?

    func take() -> Route? {
        defer { pending = nil }
        return pending
    }
}

extension PortsightMacApp {
    /// Brings the main window forward, also when it is minimized to the Dock or the app is hidden (⌘H).
    /// false when there is none, and the caller opens one: opening another next to a minimized one would leave the
    /// route to whichever window took it first.
    @MainActor static func showMainWindow() -> Bool {
        let app = NSApplication.shared
        if app.isHidden { app.unhide(nil) }
        guard let window = app.windows.first(where: {
            ($0.identifier?.rawValue.hasPrefix(mainWindowID) ?? false) && ($0.isVisible || $0.isMiniaturized)
        }) else { return false }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        return true
    }
}

private struct CloseSheetsKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// Grows when a clicked push needs the window: every sheet in it closes (`closesForPush`), so the event's page
    /// can be shown instead of waiting behind another sheet.
    var closeSheetsEpoch: Int {
        get { self[CloseSheetsKey.self] }
        set { self[CloseSheetsKey.self] = newValue }
    }
}

private struct ClosesForPush: ViewModifier {
    let close: () -> Void
    @Environment(\.closeSheetsEpoch) private var epoch

    func body(content: Content) -> some View {
        content.onChange(of: epoch) { _, _ in close() }
    }
}

extension View {
    /// Closes this view's sheet when a clicked push takes over the window (see closeSheetsEpoch).
    func closesForPush<Item>(_ item: Binding<Item?>) -> some View {
        modifier(ClosesForPush { item.wrappedValue = nil })
    }

    func closesForPush(_ isPresented: Binding<Bool>) -> some View {
        modifier(ClosesForPush { isPresented.wrappedValue = false })
    }
}

private struct DesktopSectionKey: EnvironmentKey {
    static let defaultValue: DesktopSection = .overview
}

extension EnvironmentValues {
    /// The section on screen, so the bell panel knows whether the 全部 / 个人 / 量化 scope applies.
    var desktopSection: DesktopSection {
        get { self[DesktopSectionKey.self] }
        set { self[DesktopSectionKey.self] = newValue }
    }
}

extension PortfolioDemo {
    /// Sections without the scope picker show every account notice, whatever was picked elsewhere.
    func bellScope(on section: DesktopSection) -> PortfolioScope { section.usesScope ? scope : .all }

    func bellNotices(on section: DesktopSection) -> [DemoNotice] {
        let scope = bellScope(on: section)
        return allNotices.filter { scope == .all || $0.owner == scope || $0.owner == .all }
    }

    /// Every notice the bell can open, whatever the scope: the relay's GET /notices once a relay is paired
    /// (RelayNotices), the built-in ones before.
    var allNotices: [DemoNotice] { RelayNotices.current() ?? DemoPortfolioData.notices }
}

private struct DesktopAppActiveKey: EnvironmentKey {
    static let defaultValue = true
}

private struct OpenNoticeLinkKey: EnvironmentKey {
    static let defaultValue: (RelayLink) -> Void = { _ in }
}

extension EnvironmentValues {
    /// The app is in front (NSApplication active). The relay is read on a timer only then: 总览's IBKR banner and
    /// 资产's IBKR account stop in the background and start again, with a read at once, when the app comes back.
    var desktopAppActive: Bool {
        get { self[DesktopAppActiveKey.self] }
        set { self[DesktopAppActiveKey.self] = newValue }
    }

    /// Follows a notice's link (RelayLink) from its detail page: closes the page and opens where the link points
    /// (ContentView.follow). Unknown links never get a button, so they never reach this.
    var openNoticeLink: (RelayLink) -> Void {
        get { self[OpenNoticeLinkKey.self] }
        set { self[OpenNoticeLinkKey.self] = newValue }
    }
}
