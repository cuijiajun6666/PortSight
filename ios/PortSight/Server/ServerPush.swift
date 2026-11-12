//
//  ServerPush.swift
//  PortSight
//
//  APNs pushes from the Mac mini's relay (quant_system/relay/apns.py). OFF until switched on in 服务器 → 设置, and
//  on the Mac mini (sessions/portsight/APNS_ENABLED). The device token goes to the relay over its public HTTPS address with
//  the paired device's bearer (POST /devices); a push says only the alert type and time, plus its event_id, and
//  tapping it opens that event's page (ServerEventDetailView; in 消息中心, or over a sheet that is already up, see
//  PushRoute). When the event_id is a notice id (量化保护检查 and other GET /notices entries) the notice's page
//  opens instead (ContentView). The "server offline" alert
//  cannot come from a Mac mini that is down: Healthchecks.io sends that one through the ntfy app.
//

import UIKit
import UserNotifications
import PortSightKit

extension Notification.Name {
    static let portSightOpenServer = Notification.Name("PortSight.openServer")
}

@MainActor
enum ServerPush {
    static let enabledKey = ServerPushSettings.enabledKey

    static var enabled: Bool { ServerPushSettings.enabled }

    /// Ask for permission, then register with APNs; the token arrives in PortSightAppDelegate.
    static func enable() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }
        UIApplication.shared.registerForRemoteNotifications()
        ServerStore.shared.pushSwitchChanged()
        return true
    }

    /// The relay forgets this phone's token (an empty token stops pushes to it).
    static func disable() async {
        ServerStore.shared.pushSwitchChanged()
        await ServerStore.shared.pushTurnedOff()
    }

    /// Every launch while pushes are on, and whenever iOS hands out a new token: report it again.
    static func received(_ deviceToken: Data) async {
        await ServerStore.shared.pushTokenArrived(hex(deviceToken))
    }

    nonisolated static func hex(_ token: Data) -> String { RelayAPI.hex(token) }
}

final class PortSightAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // APNs tokens can change: register again on each launch while pushes are on.
        if ServerPush.enabled { application.registerForRemoteNotifications() }
        // Reconnect to the Google Drive background upload session (家人版 uploads outlive the app).
        DriveUploader.shared.resume()
        return true
    }

    /// iOS woke the app because the Drive upload session has finished events: reconnect to it; the handler is
    /// called on the main thread from urlSessionDidFinishEvents(forBackgroundURLSession:).
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == DriveUploader.sessionIdentifier else {
            completionHandler()
            return
        }
        DriveUploader.shared.backgroundCompletionHandler = completionHandler
        DriveUploader.shared.resume()
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await ServerPush.received(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        ServerStore.shared.pushStatus = "注册推送失败：在 Xcode 的 Signing & Capabilities 里确认 Push Notifications 已打开"
    }

    // Completion-handler forms, finished on the main thread. The async forms resumed off the main thread and called
    // UIKit's completion there, which trips UIKit's main-thread assertion (crash 2026-11-09 15:59 on tapping a push).
    /// A push while the app is in front: besides the banner, read /notices now (the bell and 需要处理 show it at once)
    /// and the IBKR account and status (a trade notice must update 资产 straight away, not at the next 10 s tick).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        DispatchQueue.main.async {
            completionHandler([.banner, .list, .sound])
            guard RelayNotices.usesRelay else { return }
            Task {
                await RelayNotices.store.load(force: true)
                await IBKRStore.shared.nudge()
            }
        }
    }

    /// A relay push opens its message page (消息中心 → the event); anything else opens the 服务器 tab.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let ref = PushEventRef(userInfo: response.notification.request.content.userInfo)
        DispatchQueue.main.async {
            if let ref {
                PushRoute.shared.pending = ref
            } else {
                NotificationCenter.default.post(name: .portSightOpenServer, object: nil)
            }
            completionHandler()
        }
    }
}
