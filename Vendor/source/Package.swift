// swift-tools-version: 6.0
import PackageDescription

// Restore Log Monitor — POC 0.1
//
// Module boundary (binding, see docs/D0-SKELETON.md):
//   RestoreLogEngine      headless, SwiftUI-free capture core (the reusable asset)
//   rlmctl                headless CLI proving the engine runs without a GUI
//   RestoreLogMonitorApp  SwiftUI test harness only (no capture logic)
//
// The app target is a verification vehicle. The engine must never import SwiftUI.

let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "RestoreLogMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RestoreLogEngine", targets: ["RestoreLogEngine"]),
        .executable(name: "rlmctl", targets: ["rlmctl"]),
        .executable(name: "RestoreLogMonitorApp", targets: ["RestoreLogMonitorApp"]),
    ],
    targets: [
        .target(name: "RestoreLogEngine", swiftSettings: swiftSettings),
        .executableTarget(
            name: "rlmctl",
            dependencies: ["RestoreLogEngine"],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "RestoreLogMonitorApp",
            dependencies: ["RestoreLogEngine"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "RestoreLogEngineTests",
            dependencies: ["RestoreLogEngine"],
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        ),
    ]
)
