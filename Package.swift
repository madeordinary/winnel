// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Winnel",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Winnel", targets: ["WinnelApp"]),
        .executable(name: "WinnelFixture", targets: ["WinnelFixture"]),
        .library(name: "WinnelCore", targets: ["WinnelCore"]),
        .library(name: "WinnelStorage", targets: ["WinnelStorage"]),
        .library(name: "WinnelPlatform", targets: ["WinnelPlatform"])
    ],
    targets: [
        .target(name: "WinnelCore"),
        .executableTarget(name: "WinnelFixture"),
        .target(name: "WinnelStorage", dependencies: ["WinnelCore"]),
        .target(name: "WinnelPlatform", dependencies: ["WinnelCore"]),
        .executableTarget(name: "WinnelApp", dependencies: ["WinnelCore", "WinnelStorage", "WinnelPlatform"]),
        .testTarget(name: "WinnelAppTests", dependencies: ["WinnelApp"]),
        .testTarget(name: "WinnelCoreTests", dependencies: ["WinnelCore"]),
        .testTarget(name: "WinnelStorageTests", dependencies: ["WinnelStorage"]),
        .testTarget(name: "WinnelPlatformTests", dependencies: ["WinnelPlatform"])
    ],
    swiftLanguageModes: [.v6]
)
