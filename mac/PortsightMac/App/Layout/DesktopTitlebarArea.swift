import SwiftUI
import AppKit
import PortSightKit

/// The content scrolls up under the transparent toolbar, so a double-click on the toolbar's empty space lands on
/// the scroll view and the window never sees a title-bar double-click. This watches the window's double-clicks
/// and, when one falls in the toolbar band but not on a toolbar control, does what System Settings asks for
/// ("double-click a window's title bar to…": zoom by default, minimize, or nothing).
struct DesktopTitlebarDoubleClick: NSViewRepresentable {
    final class Watcher: NSView {
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window, event.clickCount == 2,
                      Self.isInToolbarBand(event, of: window), !Self.hitsToolbarControl(event, in: window) else { return event }
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.miniaturize(nil)
                case "None": return event
                default: window.zoom(nil)          // "Maximize" / "Fill" and the unset default
                }
                return nil
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

        private static func isInToolbarBand(_ event: NSEvent, of window: NSWindow) -> Bool {
            let band = window.frame.height - window.contentLayoutRect.maxY
            return event.locationInWindow.y >= window.frame.height - max(band, 28)
        }

        /// Only real controls (buttons, segments, menus, fields) keep their double-click; titles, glass capsule
        /// backgrounds and empty toolbar space all count as title bar. Asked through accessibility, which sees
        /// SwiftUI's controls individually where the AppKit view tree only sees whole toolbar items.
        private static func hitsToolbarControl(_ event: NSEvent, in window: NSWindow) -> Bool {
            let point = window.convertPoint(toScreen: event.locationInWindow)
            var element: AnyObject? = NSApp.accessibilityHitTest(point) as AnyObject?
            let controls: Set<NSAccessibility.Role> = [.button, .radioButton, .popUpButton, .menuButton, .checkBox,
                                                       .textField, .comboBox, .slider, .link, .incrementor]
            for _ in 0..<4 {
                guard let current = element else { return false }
                if let role = current.accessibilityRole?(), controls.contains(role) { return true }
                element = current.accessibilityParent?() as AnyObject?
            }
            return false
        }
    }

    func makeNSView(context: Context) -> Watcher { Watcher() }
    func updateNSView(_ nsView: Watcher, context: Context) {}
}
