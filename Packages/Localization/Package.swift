// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Localization",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "Localization", targets: ["Localization"]),
    ],
    targets: [
        .target(
            name: "Localization",
            resources: [.process("Resources/Localizable.xcstrings")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LocalizationTests",
            dependencies: ["Localization"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
