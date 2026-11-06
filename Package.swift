// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DeskCheck",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DeskCheckCore"),
        .executableTarget(name: "DeskCheck", dependencies: ["DeskCheckCore"]),
        .testTarget(name: "DeskCheckCoreTests", dependencies: ["DeskCheckCore"])
    ]
)
