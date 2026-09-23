// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuthClient",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AuthClient", targets: ["AuthClient"]),
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        .package(path: "../Keychain"),
        .package(path: "../NetworkClient"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "AuthClient",
            dependencies: [
                "CoreModels",
                "Keychain",
                "NetworkClient",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AuthClientTests",
            dependencies: ["AuthClient"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
