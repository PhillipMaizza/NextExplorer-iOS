// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetworkClient",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "NetworkClient", targets: ["NetworkClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "NetworkClient",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(name: "NetworkClientTests", dependencies: ["NetworkClient"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
