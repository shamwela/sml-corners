// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "sml-corners",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "sml-corners", path: "Sources/sml-corners")
    ]
)
