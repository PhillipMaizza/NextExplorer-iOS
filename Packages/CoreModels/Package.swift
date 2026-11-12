// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoreModels",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "CoreModels", targets: ["CoreModels"]),
    ],
    dependencies: [
        .package(path: "../TestUtils"),
    ],
    targets: [
        .target(name: "CoreModels", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "CoreModelsTests", dependencies: ["CoreModels", "TestUtils"], resources: [.copy("Fixtures")], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
