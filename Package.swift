// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Bastion",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Bastion",
            targets: ["Bastion"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Bastion",
            dependencies: [],
            path: "Sources/Bastion"
        ),
        .target(
            name: "BastionEngine",
            path: "Sources/BastionEngine"
        )
    ]
)
