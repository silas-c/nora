// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "desktop-ui",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "nora-ui", targets: ["NoraUI"])],
    targets: [
        .target(name: "NoraCore"),
        .executableTarget(name: "NoraUI", dependencies: ["NoraCore"]),
        .testTarget(name: "NoraCoreTests", dependencies: ["NoraCore"]),
    ]
)
