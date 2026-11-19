// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TaskManager",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "TaskManager",
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
