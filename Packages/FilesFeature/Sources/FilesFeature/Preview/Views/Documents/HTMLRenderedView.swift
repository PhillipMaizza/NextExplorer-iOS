import DesignSystem
import FilesClient
import SwiftUI
import WebKit

/// Joins an attacker influenceable relative path (archive entry name, HTML `src`/`href`
/// value) under a trusted base directory and returns it only when the standardized result
/// stays inside that base: blocks `..` traversal that would otherwise let a crafted archive
/// or HTML file write outside its sandbox folder.
enum SafeDestination {
    static func within(_ baseDirectory: URL, _ relativePath: String) -> URL? {
        let base = baseDirectory.standardizedFileURL
        let candidate = base.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path == base.path || candidate.path.hasPrefix(base.path + "/") else { return nil }
        return candidate
    }
}

/// Renders HTML as a real compiled page: the "Rendered" side of the Settings "HTML Files"
/// toggle. `loadHTMLString(_:baseURL:)` alone can't resolve relative `<link href>`/`<script
/// src>` references (there's no real base URL, the content is a fetched string, not a local
/// file): so `resolveAsset` fetches same folder assets first (from the server or, for
/// archive internal HTML, from the same open archive: see the two call sites), writes
/// everything into one local directory, and loads via `loadFileURL` instead, which does
/// resolve relative paths against its neighbors on disk.
struct HTMLRenderedView: View {
    let cacheKey: String
    let html: String
    let resolveAsset: (String) async -> URL?

    @State private var localHTMLURL: URL?
    @State private var contentRules: WKContentRuleList?

    var body: some View {
        Group {
            if let localHTMLURL, let contentRules {
                HTMLWebView(
                    fileURL: localHTMLURL,
                    readAccessURL: localHTMLURL.deletingLastPathComponent(),
                    contentRules: contentRules
                )
            } else {
                DSSpinner()
            }
        }
        .task(id: html) {
            await prepare()
        }
    }

    private func prepare() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(SessionScratchLocation.htmlPreview, isDirectory: true)
            .appendingPathComponent(cacheKey.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
        guard let mainFileURL = await Self.writePage(html, into: directory, resolveAsset: resolveAsset),
              // Without the rules the page could load remote images and styles, so it is never shown.
              let rules = await LocalOnlyContentRules.compiled(),
              !Task.isCancelled
        else { return }
        contentRules = rules
        localHTMLURL = mainFileURL
    }

    /// Writes the page and the same folder assets it references into `directory` and returns the
    /// page's file, or `nil` when it can't be written or the task was cancelled meanwhile. The file
    /// work runs off the main thread, so a large page never stalls the UI.
    static func writePage(
        _ html: String,
        into directory: URL,
        resolveAsset: (String) async -> URL?
    ) async -> URL? {
        // Always `.html`, never `fileName`'s real extension: `loadFileURL` has WebKit infer
        // MIME type from the file's own extension, and the content written here is always
        // HTML, Markdown included (converted upstream). Written out as `README.md`, WebKit
        // showed the converted HTML source as plain text instead of rendering it.
        let mainFileURL = directory.appendingPathComponent(Constants.pageFileName)
        let assetPaths: [String]? = await Task.detached(priority: .userInitiated) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard (try? html.write(to: mainFileURL, atomically: true, encoding: .utf8)) != nil else { return nil }
            return Self.relativeAssetPaths(in: html)
        }.value
        guard let assetPaths else { return nil }
        for relativePath in assetPaths {
            guard !Task.isCancelled else { return nil }
            guard let downloadedURL = await resolveAsset(relativePath) else { continue }
            // Root absolute references (`/assets/app.js`) are resolved by `resolveAsset`
            // relative to the file's own folder too (there's no real site root to anchor
            // them to): strip the leading slash to place them the same way on disk.
            let localRelativePath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
            guard let destinationURL = SafeDestination.within(directory, localRelativePath) else { continue }
            await Task.detached(priority: .userInitiated) {
                Self.place(downloadedURL, at: destinationURL)
            }.value
        }
        return Task.isCancelled ? nil : mainFileURL
    }

    private enum Constants {
        static let pageFileName = "index.html"
    }

    private nonisolated static func place(_ sourceURL: URL, at destinationURL: URL) {
        try? FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destinationURL)
        try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    /// Every `href="..."`/`src="..."` value that isn't already absolute (`http(s)://`,
    /// protocol relative `//`, `data:`, `mailto:`) or an in page anchor (`#section`); the
    /// same folder assets a fetched HTML string alone has no way to reach.
    nonisolated static func relativeAssetPaths(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:href|src)\s*=\s*["']([^"'#][^"']*)["']"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: html) else { return nil }
            let value = String(html[valueRange])
            let isAbsolute = value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("//")
                || value.hasPrefix("data:") || value.hasPrefix("mailto:")
            return isAbsolute ? nil : value
        }
    }
}

/// Resolves a relative (or root absolute) asset reference against a file's own containing
/// folder: shared by the server backed and archive backed `resolveAsset` closures so the
/// same path joining logic (and the same root absolute becomes folder relative heuristic)
/// isn't duplicated between them.
enum RelativeAssetPath {
    /// - Parameters:
    ///   - relativePath: e.g. `"style.css"`, `"../shared/app.js"`, or `"/assets/app.js"`.
    ///   - directory: the referencing file's own parent directory (server path, or archive
    ///     folder path: same string shape either way: no leading slash, `""` for the root).
    /// - Returns: `(parent, name)` split of the resolved path, or `nil` if it resolves to
    ///   nothing sensible (e.g. an empty reference).
    static func resolve(_ relativePath: String, relativeTo directory: String) -> (parent: String, name: String)? {
        // Root absolute references have no real site root to anchor to here: treat them as
        // relative to the file's own folder, the same heuristic a typical single folder
        // static site upload effectively already assumes.
        let cleanedReference = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
        // `URL(fileURLWithPath:)` resolves a relative path against the process's working
        // directory, so the folder is anchored at "/" (the volume root when it is empty) and
        // sibling paths never pick up wherever the process happens to run.
        let baseURL = URL(fileURLWithPath: "/" + directory, isDirectory: true)
        let resolvedPath = URL(fileURLWithPath: cleanedReference, relativeTo: baseURL).standardizedFileURL.path
        let cleanPath = resolvedPath.hasPrefix("/") ? String(resolvedPath.dropFirst()) : resolvedPath
        guard !cleanPath.isEmpty else { return nil }
        let parent = (cleanPath as NSString).deletingLastPathComponent
        let name = (cleanPath as NSString).lastPathComponent
        guard !name.isEmpty else { return nil }
        return (parent, name)
    }
}

/// Blocks every load that is not a local file or inline data (one rule each: WebKit's rule
/// patterns have no alternation). The navigation delegate only sees
/// page navigations: images, stylesheets, fonts and media in an untrusted page would otherwise
/// still reach the network, telling a stranger the reader's address and when the file was opened.
@MainActor
enum LocalOnlyContentRules {
    private static let identifier = "LocalOnly"
    static let encoded = """
    [{"trigger":{"url-filter":".*"},"action":{"type":"block"}},\
    {"trigger":{"url-filter":"^file:"},"action":{"type":"ignore-previous-rules"}},\
    {"trigger":{"url-filter":"^data:"},"action":{"type":"ignore-previous-rules"}}]
    """
    private static var cached: WKContentRuleList?

    /// Compiled once per run; `nil` only when WebKit refuses the rules.
    static func compiled() async -> WKContentRuleList? {
        if let cached {
            return cached
        }
        let rules = try? await WKContentRuleListStore.default()?.compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: encoded
        )
        cached = rules
        return rules
    }

    /// The configuration every rendered page loads with. The content is an untrusted file from the
    /// user's server (or an archive): JavaScript is disabled so a hostile page can't read
    /// neighbouring files off disk, `rules` block every remote load, and the navigation delegate
    /// pins navigation to the local file.
    static func webViewConfiguration(applying rules: WKContentRuleList) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(rules)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        // No shared cookie or storage jar for untrusted server content: nothing to reach even if
        // disabled scripts and pinned navigation were somehow bypassed.
        configuration.websiteDataStore = .nonPersistent()
        return configuration
    }
}

@MainActor
private struct HTMLWebView {
    let fileURL: URL
    let readAccessURL: URL
    let contentRules: WKContentRuleList

    fileprivate func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = LocalOnlyContentRules.webViewConfiguration(applying: contentRules)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
        return webView
    }

    fileprivate func updateWebView(_ webView: WKWebView, coordinator: Coordinator) {
        guard coordinator.lastLoadedURL != fileURL else { return }
        coordinator.lastLoadedURL = fileURL
        webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(lastLoadedURL: fileURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedURL: URL

        init(lastLoadedURL: URL) {
            self.lastLoadedURL = lastLoadedURL
        }

        func webView(
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            navigationAction.request.url?.isFileURL == true ? .allow : .cancel
        }
    }
}

#if os(iOS)
    extension HTMLWebView: UIViewRepresentable {
        func makeUIView(context: Context) -> WKWebView {
            makeWebView(coordinator: context.coordinator)
        }

        func updateUIView(_ uiView: WKWebView, context: Context) {
            updateWebView(uiView, coordinator: context.coordinator)
        }
    }
#else
    extension HTMLWebView: NSViewRepresentable {
        func makeNSView(context: Context) -> WKWebView {
            makeWebView(coordinator: context.coordinator)
        }

        func updateNSView(_ nsView: WKWebView, context: Context) {
            updateWebView(nsView, coordinator: context.coordinator)
        }
    }
#endif
