// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FilesFeature",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "FilesFeature", targets: ["FilesFeature"]),
    ],
    dependencies: [
        .package(path: "../AppStorageKeys"),
        .package(path: "../ClientCertificateFeature"),
        .package(path: "../CoreModels"),
        .package(path: "../FilesClient"),
        .package(path: "../NetworkClient"),
        .package(path: "../DesignSystem"),
        .package(path: "../Localization"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.17.0"),
        // Direct pin so the test target can reach `DependenciesTestSupport` (the `.dependencies`
        // test trait): it ships in swift-dependencies, which TCA already pulls in transitively.
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.0"),
        .package(url: "https://github.com/simonbs/TreeSitterLanguages", from: "0.1.10"),
        // Runestone's own tree sitter; the macOS editor drives it directly (Runestone is UIKit only).
        .package(url: "https://github.com/tree-sitter/tree-sitter", .upToNextMinor(from: "0.20.9")),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.19"),
        .package(url: "https://github.com/mtgto/Unrar.swift", from: "0.5.4"),
        // libvlc (VideoLAN) as a binary xcframework, for the video/audio containers and codecs
        // AVFoundation can't decode (avi, webm, mkv, wmv, flv, mpg, mpeg; ogg, opus, wma):
        // parity with the web client's player.
        .package(url: "https://github.com/tylerjonesio/vlckit-spm", exact: "3.6.0"),
        // Releases follow the Swift toolchain (0.9 shipped with Swift 6.4), cut on a release
        // branch with a proper semver tag.
        .package(url: "https://github.com/apple/swift-markdown", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "FilesFeature",
            dependencies: [
                "AppStorageKeys",
                "ClientCertificateFeature",
                "CoreModels",
                "FilesClient",
                "NetworkClient",
                "DesignSystem",
                "Localization",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                // Client-side archive listing (`ArchiveBrowserView`): the server has no
                // listing-only endpoint (`POST /api/files/zip/extract` fully unpacks to disk),
                // so reading a .zip/.rar's contents happens entirely on-device instead.
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "Unrar", package: "Unrar.swift"),
                .product(name: "VLCKitSPM", package: "vlckit-spm"),
                .product(name: "Markdown", package: "swift-markdown"),
                // Curated to the code/text kinds `FileTypeIcon`'s badge table already covers:
                // TreeSitterLanguages has 70+, most of which this app never encounters.
                .product(name: "TreeSitterJSONRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterJavaScriptRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterTypeScriptRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterTSXRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterHTMLRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterCSSRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterSCSSRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterPythonRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterRubyRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterPHPRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterGoRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterRustRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterJavaRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterCRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterCPPRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterCSharpRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterSQLRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterYAMLRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterTOMLRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterMarkdownRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterBashRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterSwiftRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitter", package: "tree-sitter", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterJSON", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterJSONQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterJavaScript", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterJavaScriptQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterTypeScript", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterTypeScriptQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterTSX", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterTSXQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterHTML", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterHTMLQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterCSS", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterCSSQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterSCSS", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterSCSSQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterPython", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterPythonQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterRuby", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterRubyQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterPHP", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterPHPQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterGo", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterGoQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterRust", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterRustQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterJava", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterJavaQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterC", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterCQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterCPP", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterCPPQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterCSharp", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterCSharpQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterSQL", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterSQLQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterYAML", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterYAMLQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterTOML", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterTOMLQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterMarkdown", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterMarkdownQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterBash", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterBashQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterSwift", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
                .product(name: "TreeSitterSwiftQueries", package: "TreeSitterLanguages", condition: .when(platforms: [.macOS])),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)],
            // SwiftUI's VideoPlayer wraps AVKit's player view, but on macOS 27 its overlay no
            // longer loads AVKit itself and nothing links it automatically: opening a video
            // crashed unless something else had loaded AVKit first.
            linkerSettings: [.linkedFramework("AVKit")]
        ),
        .testTarget(
            name: "FilesFeatureTests",
            dependencies: [
                "FilesFeature",
                .product(name: "ClientCertificateFeature", package: "ClientCertificateFeature"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Localization", package: "Localization"),
                .product(name: "NetworkClient", package: "NetworkClient"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
