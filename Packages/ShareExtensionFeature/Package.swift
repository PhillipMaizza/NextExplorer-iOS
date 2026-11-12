// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShareExtensionFeature",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ShareExtensionFeature", targets: ["ShareExtensionFeature"]),
    ],
    dependencies: [
        .package(path: "../TestUtils"),
        .package(path: "../AuthClient"),
        .package(path: "../CoreModels"),
        .package(path: "../DesignSystem"),
        .package(path: "../FilesClient"),
        .package(path: "../FolderPickerFeature"),
        .package(path: "../Localization"),
        .package(path: "../NetworkClient"),
        .package(path: "../ShareUploads"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.17.0"),
    ],
    targets: [
        .target(
            name: "ShareExtensionFeature",
            dependencies: [
                "AuthClient",
                "CoreModels",
                "DesignSystem",
                "FilesClient",
                "FolderPickerFeature",
                "Localization",
                "NetworkClient",
                "ShareUploads",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ShareExtensionFeatureTests",
            dependencies: [
                "TestUtils",
                "ShareExtensionFeature",
                .product(name: "NetworkClient", package: "NetworkClient"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
