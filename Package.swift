// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeviceCapturePrototype",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "DeviceCapturePrototype", targets: ["DeviceCapturePrototype"]),
        .executable(name: "mra-helper", targets: ["MRAHelper"]),
    ],
    dependencies: [
        .package(path: "Vendor/source"),
    ],
    targets: [
        .target(name: "MRAHelperProtocol"),
        .target(
            name: "MRAHelperCore",
            dependencies: ["MRAHelperProtocol"],
            path: "Sources/MRAHelper",
            exclude: ["HelperMain.swift"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MRAHelper",
            dependencies: ["MRAHelperProtocol", "MRAHelperCore"],
            path: "Sources/MRAHelper",
            exclude: ["HelperCore.swift", "HostPortTextParser.swift"],
            sources: ["HelperMain.swift"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DeviceCapturePrototype",
            dependencies: [
                .product(name: "RestoreLogEngine", package: "source"),
                "MRAHelperProtocol",
                "MRAHelperCore",
            ],
            resources: [
                .copy("builtin-calibrations.json"),
                .copy("fixed-model-catalog.json"),
                .copy("mac-model-catalog.v2.json"),
                .copy("mac-hardware-identity.v1.json"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DeviceCapturePrototypeTests",
            dependencies: ["DeviceCapturePrototype"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MRAHelperTests",
            dependencies: ["MRAHelperProtocol", "MRAHelperCore"],
            resources: [.copy("Fixtures/stub_direct_rid_dfu.sh")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MRA022AcceptanceTests",
            dependencies: ["DeviceCapturePrototype", "MRAHelperProtocol", "MRAHelperCore"],
            exclude: ["README.md"],
            resources: [
                .copy("Fixtures"),
                .copy("Scripts"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
