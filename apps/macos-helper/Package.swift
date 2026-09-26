// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macos-helper",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "mac-helper", targets: ["mac-helper"])],
    targets: [.executableTarget(name: "mac-helper")]
)
