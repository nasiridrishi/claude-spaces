// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClaudeSpaces",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClaudeSpaces", path: "Sources/ClaudeSpaces")
    ]
)
