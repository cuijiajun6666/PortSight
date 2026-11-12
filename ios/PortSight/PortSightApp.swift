//
//  PortSightApp.swift
//  PortSight
//
//  Created by Chris Cui on 28/4/2026.
//

import SwiftUI
import SwiftData
import PortSightKit

@main
struct PortSightApp: App {
    @UIApplicationDelegateAdaptor(PortSightAppDelegate.self) private var appDelegate
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            AssetSnapshotRecord.self,
            StockLogoRecord.self,
            ])
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isPreview || DemoPortfolioData.enabled)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        if DemoPortfolioData.enabled {
            URLProtocol.registerClass(DemoOfflineProtocol.self)
        }
    }

    var body: some Scene {
        WindowGroup {
            AppEditionRoot()
        }
        .modelContainer(sharedModelContainer)
    }
}

/// 完整版 or 家人版 (设置 → 家人版). The family edition is the photo library only.
struct AppEditionRoot: View {
    @AppStorage(AppEdition.storageKey) private var familyEdition = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if familyEdition {
                FamilyEditionView().transition(.blurReplace)
            } else {
                ContentView().transition(.blurReplace)
            }
        }
        .animation(.smooth(duration: 0.4), value: familyEdition)
        // 家人版 has no 消息中心: a tapped relay push shows its event's page on top (完整版: ContentView takes it).
        .onChange(of: PushRoute.shared.pending, initial: true) { _, ref in
            guard familyEdition, let ref else { return }
            PushRoute.shared.pending = nil
            PushRoute.presentOverTop(.event(ref))
        }
        // Google Drive uploads: continue (from where Drive says they got) each time the app comes back; failed
        // uploads are only retried while the app is in the foreground.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { DriveUploader.shared.resume() }
            if phase == .background { DriveUploader.shared.pauseRetries() }
        }
        // 完整版 opening or coming back: the Mac mini's data (host, alerts, notices, calendar, news; at most every
        // 30 s by itself) and the IBKR login state at once, so the banner and the bell are right from the start.
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active, !familyEdition else { return }
            Task {
                await ServerStore.shared.refresh()
                await IBKRStore.shared.refreshStatus(force: true)
            }
        }
    }
}
