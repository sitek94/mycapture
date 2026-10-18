// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyCapture",
    platforms: [.macOS(.v26)],
    products: [
        // Lowercase-first on purpose: the app and its process are called "myCapture".
        .executable(name: "myCapture", targets: ["MyCapture"]),
        .executable(name: "myCaptureDriver", targets: ["MyCaptureDriver"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sitek94/mykit", from: "0.6.0"),
        // Pins the SwiftLint binary that scripts/check.sh runs (same version as myKit); no target uses it.
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.65.1"),
    ],
    targets: [
        .target(name: "MyCaptureCore"),
        .executableTarget(
            name: "MyCapture",
            dependencies: ["MyCaptureCore", .product(name: "MyKit", package: "mykit")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(name: "MyCaptureDriver"),
        .testTarget(name: "MyCaptureCoreTests", dependencies: ["MyCaptureCore"]),
    ]
)
