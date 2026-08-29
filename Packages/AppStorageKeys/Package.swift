// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppStorageKeys",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "AppStorageKeys", targets: ["AppStorageKeys"])
    ],
    targets: [
        .target(name: "AppStorageKeys", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "AppStorageKeysTests", dependencies: ["AppStorageKeys"], swiftSettings: [.swiftLanguageMode(.v6)])
    ]
)
