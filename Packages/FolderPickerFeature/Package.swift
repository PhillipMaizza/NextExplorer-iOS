// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FolderPickerFeature",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "FolderPickerFeature", targets: ["FolderPickerFeature"]),
    ],
    dependencies: [
        .package(path: "../TestUtils"),
        .package(path: "../CoreModels"),
        .package(path: "../DesignSystem"),
        .package(path: "../FilesClient"),
        .package(path: "../Localization"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.17.0"),
    ],
    targets: [
        .target(
            name: "FolderPickerFeature",
            dependencies: [
                "CoreModels",
                "DesignSystem",
                "FilesClient",
                "Localization",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FolderPickerFeatureTests",
            dependencies: [
                "TestUtils",
                "FolderPickerFeature",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
