// swift-tools-version: 6.0
import PackageDescription

// A small test package for the app's CLI and state logic. Run the app through Xcode.
let package = Package(
    name: "CKitCore",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "CKitCore", path: "CKit/Core"),
        .testTarget(name: "CKitCoreTests", dependencies: ["CKitCore"], path: "Tests"),
    ]
)
