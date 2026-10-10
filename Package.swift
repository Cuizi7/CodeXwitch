// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CodeXwitch",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CodeXwitchKit", targets: ["CodeXwitchKit"]),
               .executable(name: "CodeXwitch", targets: ["CodeXwitch"])],
    targets: [
        .target(name: "CodeXwitchKit", resources: [.copy("Resources/Icons")]),
        .executableTarget(name: "CodeXwitch", dependencies: ["CodeXwitchKit"]),
        .testTarget(name: "CodeXwitchKitTests", dependencies: ["CodeXwitchKit"])
    ]
)
