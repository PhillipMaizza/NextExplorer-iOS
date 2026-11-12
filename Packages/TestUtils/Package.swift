// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TestUtils",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "TestUtils", targets: ["TestUtils"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.0"),
    ],
    targets: [
        .target(
            name: "TestUtils",
            dependencies: [.product(name: "Dependencies", package: "swift-dependencies")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
