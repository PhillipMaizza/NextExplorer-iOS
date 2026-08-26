// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Keychain",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "Keychain", targets: ["Keychain"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "Keychain",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(name: "KeychainTests", dependencies: ["Keychain"], swiftSettings: [.swiftLanguageMode(.v6)])
    ]
)
