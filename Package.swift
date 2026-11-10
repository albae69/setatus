// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Setatus",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Setatus", path: "Sources/Setatus")
    ]
)
