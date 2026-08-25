// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppFeature",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "AppFeature", targets: ["AppFeature"])
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        .package(path: "../AuthClient"),
        .package(path: "../AuthFeature"),
        .package(path: "../FilesClient"),
        .package(path: "../FilesFeature"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.17.0")
    ],
    targets: [
        .target(
            name: "AppFeature",
            dependencies: [
                "CoreModels",
                "AuthClient",
                "AuthFeature",
                "FilesClient",
                "FilesFeature",
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
