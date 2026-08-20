// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "tunaneko",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "tunaneko",
            path: "Sources/tunaneko"
        )
    ]
)
