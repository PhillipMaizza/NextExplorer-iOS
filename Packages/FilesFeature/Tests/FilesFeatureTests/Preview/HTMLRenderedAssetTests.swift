@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// The rendered HTML preview reads `href`/`src` values out of an untrusted page and fetches the
/// relative ones from the file's own folder; everything else must stay out of reach.
struct HTMLRenderedAssetTests {
    struct ScanCase: Sendable, CustomTestStringConvertible {
        let html: String
        let expected: [String]

        var testDescription: String {
            html
        }
    }

    struct ResolveCase: Sendable, CustomTestStringConvertible {
        let reference: String
        let directory: String
        let parent: String
        let name: String

        var testDescription: String {
            "\(reference) in \(directory)"
        }
    }

    @Test("Only relative references are picked up from a page", arguments: [
        ScanCase(html: #"<link rel="stylesheet" href="style.css">"#, expected: ["style.css"]),
        ScanCase(html: "<img src='img/a.png'>", expected: ["img/a.png"]),
        ScanCase(html: #"<script SRC = "/assets/app.js"></script>"#, expected: ["/assets/app.js"]),
        ScanCase(html: #"<img src="../shared/a.png">"#, expected: ["../shared/a.png"]),
        ScanCase(html: ##"<a href="#top">Top</a>"##, expected: []),
        ScanCase(html: #"<img src="https://example.com/pixel.png">"#, expected: []),
        ScanCase(html: #"<img src="http://example.com/pixel.png">"#, expected: []),
        ScanCase(html: #"<script src="//cdn.example.com/x.js"></script>"#, expected: []),
        ScanCase(html: #"<img src="data:image/png;base64,AAAA">"#, expected: []),
        ScanCase(html: #"<a href="mailto:someone@example.com">Mail</a>"#, expected: []),
        ScanCase(html: "<p>No references at all</p>", expected: []),
    ])
    func scansRelativeReferences(_ testCase: ScanCase) {
        #expect(HTMLRenderedView.relativeAssetPaths(in: testCase.html) == testCase.expected)
    }

    @Test("References resolve against the file's own folder and never climb above the root", arguments: [
        ResolveCase(reference: "style.css", directory: "docs", parent: "docs", name: "style.css"),
        ResolveCase(reference: "../shared/app.js", directory: "docs/site", parent: "docs/shared", name: "app.js"),
        ResolveCase(reference: "/assets/app.js", directory: "docs", parent: "docs/assets", name: "app.js"),
        ResolveCase(reference: "style.css", directory: "", parent: "", name: "style.css"),
        ResolveCase(reference: "../../../../secret.txt", directory: "docs", parent: "", name: "secret.txt"),
    ])
    func resolvesAgainstTheFolder(_ testCase: ResolveCase) throws {
        let resolved = try #require(RelativeAssetPath.resolve(testCase.reference, relativeTo: testCase.directory))
        #expect(resolved.parent == testCase.parent)
        #expect(resolved.name == testCase.name)
    }

    /// A fresh folder holding one asset file every reference resolves to.
    private func makeAsset() throws -> (root: URL, asset: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Constants.directoryPrefix)\(TestID.name())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let asset = root.appendingPathComponent(Constants.assetName)
        try Data(Constants.assetBody.utf8).write(to: asset)
        return (root, asset)
    }

    @MainActor
    @Test("The page and its assets land in its folder; a reference that climbs out is never written")
    func writesThePageAndItsAssets() async throws {
        let (root, asset) = try makeAsset()
        defer { try? FileManager.default.removeItem(at: root) }
        let pageFolder = root.appendingPathComponent(Constants.pageFolder, isDirectory: true)

        let page = await HTMLRenderedView.writePage(Constants.page, into: pageFolder) { _ in asset }

        let pageURL = try #require(page)
        #expect(pageURL.lastPathComponent == "index.html")
        #expect(try String(contentsOf: pageURL, encoding: .utf8) == Constants.page)
        let styles = pageFolder.appendingPathComponent("css/style.css")
        let script = pageFolder.appendingPathComponent("js/app.js")
        #expect(try String(contentsOf: styles, encoding: .utf8) == Constants.assetBody)
        #expect(try String(contentsOf: script, encoding: .utf8) == Constants.assetBody)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.png").path))
    }

    @MainActor
    @Test("A preparation cancelled while fetching assets returns no page to show")
    func cancelledPreparationReturnsNothing() async throws {
        let (root, asset) = try makeAsset()
        defer { try? FileManager.default.removeItem(at: root) }
        let pageFolder = root.appendingPathComponent(Constants.pageFolder, isDirectory: true)

        let page = await HTMLRenderedView.writePage(Constants.page, into: pageFolder) { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return asset
        }

        #expect(page == nil)
    }
}

private enum Constants {
    static let directoryPrefix = "html-page-"
    static let pageFolder = "page"
    static let assetName = "asset.txt"
    static let assetBody = "asset body"
    static let page = """
    <link rel="stylesheet" href="css/style.css"><img src="../escape.png"><script src="/js/app.js"></script>
    """
}
