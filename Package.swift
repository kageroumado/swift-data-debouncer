// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftDataDebouncer",
    platforms: [.macOS(.v14), .iOS(.v17), .macCatalyst(.v17), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1)],
    products: [
        .library(name: "SwiftDataDebouncer", targets: ["SwiftDataDebouncer"]),
    ],
    targets: [
        .target(
            name: "SwiftDataDebouncer",
            swiftSettings: [.swiftLanguageMode(.v6)],
        ),
        .testTarget(
            name: "SwiftDataDebouncerTests",
            dependencies: ["SwiftDataDebouncer"],
            swiftSettings: [.swiftLanguageMode(.v6)],
        ),
    ],
)
