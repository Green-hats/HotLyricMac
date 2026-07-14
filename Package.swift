// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HotLyricMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "HotLyricMac", targets: ["HotLyricMac"])
    ],
    targets: [
        .executableTarget(
            name: "HotLyricMac",
            path: "Sources/HotLyricMac",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "HotLyricMacTests",
            dependencies: ["HotLyricMac"],
            path: "Tests/HotLyricMacTests"
        )
    ]
)
