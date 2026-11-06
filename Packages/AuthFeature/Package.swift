// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuthFeature",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AuthFeature", targets: ["AuthFeature"]),
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        .package(path: "../AuthClient"),
        .package(path: "../ClientCertificateFeature"),
        .package(path: "../NetworkClient"),
        .package(path: "../DesignSystem"),
        .package(path: "../Localization"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.17.0"),
    ],
    targets: [
        .target(
            name: "AuthFeature",
            dependencies: [
                "CoreModels",
                "AuthClient",
                "ClientCertificateFeature",
                "DesignSystem",
                "NetworkClient",
                "Localization",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AuthFeatureTests",
            dependencies: [
                "AuthFeature",
                "ClientCertificateFeature",
                "NetworkClient",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
