// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TestUtils",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "TestUtils", targets: ["TestUtils"]),
    ],
    targets: [
        .target(name: "TestUtils", swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
