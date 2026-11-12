//
//  DesktopServerPush.swift
//  PortsightMac
//
//  APNs on the Mac, same as iOS: one bundle ID (com.chriscui.portsight), so the relay's single APNs topic reaches
//  both. OFF until switched on in 设置 → 量化服务器. The token goes to the relay with the paired device's bearer
//  (POST /devices, see ServerStore); it is reported on every launch while pushes are on, and whenever macOS hands
//  out a new one. Clicking a relay push opens the bell panel with that event's page: the notice's page when its
//  event_id is a notice id (quant protection pushes, "protect:…"), 总览's IBKR banner for a re-authorization, else
//  the alert page (DesktopServerEventDetail); any other notification opens the 服务器 section (ContentView.show).
//  A push arriving while the app is in front reads /notices and the IBKR account at once (a trade notice must show
//  in the account straight away); coming back to the front refreshes the relay and the IBKR login state.
//

import AppKit
import UserNotifications
import PortSightKit

extension Notification.Name {
    static let portSightOpenServer = Notification.Name("PortSight.openServer")
}

@MainActor
enum DesktopServerPush {
    /// Ask for permission, then register with APNs; the token arrives in DesktopAppDelegate.
    static func enable() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }
        NSApplication.shared.registerForRemoteNotifications()
        ServerStore.shared.pushSwitchChanged()
        return true
    }

    /// The relay forgets this Mac's token (an empty token stops pushes to it).
    static func disable() async {
        ServerStore.shared.pushSwitchChanged()
        await ServerStore.shared.pushTurnedOff()
    }
}

final class DesktopAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        // APNs tokens can change: register again on each launch while pushes are on.
        if ServerPushSettings.enabled { NSApplication.shared.registerForRemoteNotifications() }
    }

    /// Back in front (also right after launch): read the relay now instead of at the menu bar's next minute, and ask
    /// whether IBKR still needs re-authorizing. refresh() keeps automatic reads at least 30 s apart by itself.
    func applicationDidBecomeActive(_ notification: Notification) {
        Task {
            await ServerStore.shared.refresh()
            await IBKRStore.shared.refreshStatus(force: true)
        }
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await ServerStore.shared.pushTokenArrived(RelayAPI.hex(deviceToken)) }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        ServerStore.shared.pushStatus = "注册推送失败：在 Xcode 的 Signing & Capabilities 里确认 Push Notifications 已打开"
    }

    // Completion-handler forms, finished on the main thread (the async forms call the system's completion off the
    // main thread; on iOS that crashed when a push was tapped).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        DispatchQueue.main.async { completionHandler([.banner, .list, .sound]) }
        // A notice (or a personal trade) just arrived: the bell and the IBKR account should show it now, not at the
        // next refresh. Both stores still keep their own limits.
        Task { @MainActor in
            guard RelayNotices.usesRelay else { return }
            await RelayNotices.store.load(force: true)
            await IBKRStore.shared.nudge()
        }
    }

    /// Picked up by the menu bar label (always alive), which opens the main window on that event (or on 服务器).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let ref = PushEventRef(userInfo: response.notification.request.content.userInfo)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .portSightOpenServer, object: ref)
            completionHandler()
        }
    }
}
