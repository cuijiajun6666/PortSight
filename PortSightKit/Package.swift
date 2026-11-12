// swift-tools-version: 6.2
// PortSightKit: everything below the screens, shared by the iOS app (PortSight) and the Mac app (PortsightMac).
// Models, view models, clients, cache and the demo fixtures live here; each app keeps only its own SwiftUI pages.
import PackageDescription

let package = Package(
    name: "PortSightKit",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.5"), .macOS("27.0")],
    products: [
        .library(name: "PortSightKit", targets: ["PortSightKit"]),
    ],
    targets: [
        .target(
            name: "PortSightKit",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                // Same as both app targets (SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor), so moved code behaves unchanged.
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "PortSightKitTests",
            dependencies: ["PortSightKit"],
            swiftSettings: [.swiftLanguageMode(.v5), .defaultIsolation(MainActor.self)]
        ),
    ]
)
