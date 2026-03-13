// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Prune",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Prune",
            path: "Sources"
        )
    ]
)
