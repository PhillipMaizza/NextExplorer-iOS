// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"])
    ],
    dependencies: [
        .package(path: "../AppStorageKeys")
    ],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: ["AppStorageKeys"],
            resources: [
                .process("Resources/Colors.xcassets"),
                .process("Resources/Images.xcassets"),
                .copy("Resources/Fonts")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"], swiftSettings: [.swiftLanguageMode(.v6)])
    ]
)
