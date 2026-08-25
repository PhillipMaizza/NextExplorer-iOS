// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FilesFeature",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "FilesFeature", targets: ["FilesFeature"])
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        .package(path: "../FilesClient"),
        .package(path: "../DesignSystem"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.17.0")
    ],
    targets: [
        .target(
            name: "FilesFeature",
            dependencies: [
                "CoreModels",
                "FilesClient",
                "DesignSystem",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FilesFeatureTests",
            dependencies: [
                "FilesFeature",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
