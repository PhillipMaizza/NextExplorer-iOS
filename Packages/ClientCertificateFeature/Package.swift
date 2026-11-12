// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClientCertificateFeature",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ClientCertificateFeature", targets: ["ClientCertificateFeature"]),
    ],
    dependencies: [
        .package(path: "../TestUtils"),
        .package(path: "../NetworkClient"),
        .package(path: "../DesignSystem"),
        .package(path: "../Localization"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.17.0"),
    ],
    targets: [
        .target(
            name: "ClientCertificateFeature",
            dependencies: [
                "NetworkClient",
                "DesignSystem",
                "Localization",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ClientCertificateFeatureTests",
            dependencies: [
                "TestUtils",
                "ClientCertificateFeature",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
