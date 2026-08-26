// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FilesFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "FilesFeature", targets: ["FilesFeature"])
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        .package(path: "../FilesClient"),
        .package(path: "../DesignSystem"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.17.0"),
        .package(url: "https://github.com/simonbs/TreeSitterLanguages", from: "0.1.10"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.19"),
        .package(url: "https://github.com/mtgto/Unrar.swift", from: "0.5.4"),
        // No semver release tags exist (Apple ties this one to Swift toolchain snapshot tags
        // instead) — pinned to an exact commit on `main` rather than a moving branch, so this
        // stays fully reproducible.
        .package(url: "https://github.com/apple/swift-markdown", revision: "27b7fc1a19068bcea3d2072db0ce86360d1400ed")
    ],
    targets: [
        .target(
            name: "FilesFeature",
            dependencies: [
                "CoreModels",
                "FilesClient",
                "DesignSystem",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                // Client-side archive listing (`ArchiveBrowserView`) — the server has no
                // listing-only endpoint (`POST /api/files/zip/extract` fully unpacks to disk),
                // so reading a .zip/.rar's contents happens entirely on-device instead.
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "Unrar", package: "Unrar.swift"),
                .product(name: "Markdown", package: "swift-markdown"),
                // Curated to the code/text kinds `FileTypeIcon`'s badge table already covers —
                // TreeSitterLanguages has 70+, most of which this app never encounters.
                .product(name: "TreeSitterJSONRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterJavaScriptRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterTypeScriptRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterTSXRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterHTMLRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterCSSRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterSCSSRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterPythonRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterRubyRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterPHPRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterGoRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterRustRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterJavaRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterCRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterCPPRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterCSharpRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterSQLRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterYAMLRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterTOMLRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterMarkdownRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterBashRunestone", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterSwiftRunestone", package: "TreeSitterLanguages")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FilesFeatureTests",
            dependencies: [
                "FilesFeature",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
