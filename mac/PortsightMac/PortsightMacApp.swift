import SwiftUI
import SwiftData
import PortSightKit

@main
struct PortsightMacApp: App {
    static let mainWindowID = "main"
    /// APNs registration and push clicks (DesktopServerPush.swift).
    @NSApplicationDelegateAdaptor(DesktopAppDelegate.self) private var appDelegate
    @StateObject private var terminal = TerminalDemo()
    /// App-wide so read state and scope survive closing and reopening the main window.
    @StateObject private var demo = PortfolioDemo()
    @StateObject private var router = DesktopRouter()
    /// App-wide so queued photos keep uploading after the upload sheet or the main window closes.
    @StateObject private var uploads = PhotoUploadQueue()
    @ObservedObject private var server = ServerStore.shared

    // Deliberately offline, matching the current iOS visual prototype.
    // Original broker clients remain in Core for the later data integration.
    private let container: ModelContainer = {
        let schema = Schema([Item.self, AssetSnapshotRecord.self, StockLogoRecord.self])
        return try! ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
    }()

    init() { URLProtocol.registerClass(DemoOfflineProtocol.self) }

    var body: some Scene {
        WindowGroup("PortSight", id: Self.mainWindowID) {
            ContentView().frame(minWidth: 1060, minHeight: 560)
                .environmentObject(terminal)
                .environmentObject(uploads)
                .environmentObject(demo)
                .environmentObject(router)
        }
        .modelContainer(container)
        .defaultSize(width: 1480, height: 980)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing: .newItem) { } }

        MenuBarExtra {
            PortSightMenuBarContent(store: server, terminal: terminal, router: router)
        } label: {
            PortSightMenuBarLabel(store: server, router: router)
        }
        .menuBarExtraStyle(.window)
    }
}
