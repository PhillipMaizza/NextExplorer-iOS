// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "AppFeature", targets: ["AppFeature"])
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        .package(path: "../AppStorageKeys"),
        .package(path: "../AuthClient"),
        .package(path: "../AuthFeature"),
        .package(path: "../DesignSystem"),
        .package(path: "../FilesClient"),
        .package(path: "../FilesFeature"),
        .package(path: "../Localization"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.17.0")
    ],
    targets: [
        .target(
            name: "AppFeature",
            dependencies: [
                "CoreModels",
                "AppStorageKeys",
                "AuthClient",
                "AuthFeature",
                "DesignSystem",
                "FilesClient",
                "FilesFeature",
                "Localization",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AppFeatureTests",
            dependencies: [
                "AppFeature",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
