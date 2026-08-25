// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FilesClient",
    platforms: [.iOS(.v18), .macOS(.v13)],
    products: [
        .library(name: "FilesClient", targets: ["FilesClient"])
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        .package(path: "../NetworkClient"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "FilesClient",
            dependencies: [
                "CoreModels",
                "NetworkClient",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FilesClientTests",
            dependencies: ["FilesClient", "NetworkClient"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
