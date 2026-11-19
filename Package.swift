// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tessu",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tessu", targets: ["Tessu"]),
    ],
    targets: [
        // Network engine, AI agents, key storage. No UI, so it can be tested and smoke-tested on its own.
        .target(name: "TessuCore", path: "Sources/TessuCore"),
        // The SwiftUI app.
        .executableTarget(name: "Tessu", dependencies: ["TessuCore"], path: "Sources/Tessu"),
        // Command-line harness that runs the real engine against the real network.
        .executableTarget(name: "tessu-smoke", dependencies: ["TessuCore"], path: "Sources/TessuSmoke"),
        .testTarget(
            name: "TessuCoreTests",
            dependencies: ["TessuCore"],
            path: "Tests/TessuCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
