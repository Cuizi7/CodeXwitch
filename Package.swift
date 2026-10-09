// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CodeXwitch",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CodeXwitchKit", targets: ["CodeXwitchKit"])],
    targets: [
        .target(name: "CodeXwitchKit"),
        .testTarget(name: "CodeXwitchKitTests", dependencies: ["CodeXwitchKit"])
    ]
)
