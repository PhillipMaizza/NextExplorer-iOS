// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShareUploads",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ShareUploads", targets: ["ShareUploads"]),
    ],
    dependencies: [
        .package(path: "../TestUtils"),
        .package(path: "../CoreModels"),
        .package(path: "../FilesClient"),
        .package(path: "../NetworkClient"),
        .package(path: "../Localization"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "ShareUploads",
            dependencies: [
                "CoreModels",
                "FilesClient",
                "NetworkClient",
                "Localization",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ShareUploadsTests",
            dependencies: ["TestUtils", "ShareUploads"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
