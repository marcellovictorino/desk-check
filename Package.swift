// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DeskUndo",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DeskUndoCore"),
        .executableTarget(name: "DeskUndo", dependencies: ["DeskUndoCore"])
    ]
)
