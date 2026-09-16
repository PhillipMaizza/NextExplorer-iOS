// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoreModels",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "CoreModels", targets: ["CoreModels"]),
    ],
    targets: [
        .target(name: "CoreModels", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "CoreModelsTests", dependencies: ["CoreModels"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
