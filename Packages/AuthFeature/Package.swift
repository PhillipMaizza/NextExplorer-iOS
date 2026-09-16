// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuthFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "AuthFeature", targets: ["AuthFeature"]),
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        .package(path: "../AuthClient"),
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
                "DesignSystem",
                "Localization",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AuthFeatureTests",
            dependencies: [
                "AuthFeature",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
