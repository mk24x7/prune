// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Prune",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "PruneDefinitions",
            path: "Definitions",
            exclude: ["artifacts.schema.json", "validate.mjs"],
            resources: [.copy("artifacts.json")]
        ),
        .target(
            name: "PruneCore",
            dependencies: ["PruneDefinitions"],
            path: "Sources/PruneCore"
        ),
        .executableTarget(
            name: "Prune",
            dependencies: ["PruneCore"],
            path: "Sources/Prune"
        ),
        .testTarget(
            name: "PruneCoreTests",
            dependencies: ["PruneCore"],
            path: "Tests/PruneCoreTests"
        ),
    ]
)
