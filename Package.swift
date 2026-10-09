// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WheredItGo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WheredItGo",
            path: "Sources/WheredItGo"
        ),
    ]
)
