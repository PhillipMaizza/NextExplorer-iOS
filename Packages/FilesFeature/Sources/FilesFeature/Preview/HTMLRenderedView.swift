import DesignSystem
import SwiftUI
import WebKit

/// Joins an attacker influenceable relative path (archive entry name, HTML `src`/`href`
/// value) under a trusted base directory and returns it only when the standardized result
/// stays inside that base — blocks `..` traversal that would otherwise let a crafted archive
/// or HTML file write outside its sandbox folder.
enum SafeDestination {
    static func within(_ baseDirectory: URL, _ relativePath: String) -> URL? {
        let base = baseDirectory.standardizedFileURL
        let candidate = base.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path == base.path || candidate.path.hasPrefix(base.path + "/") else { return nil }
        return candidate
    }
}

/// Renders HTML as a real compiled page — the "Rendered" side of the Settings "HTML Files"
/// toggle. `loadHTMLString(_:baseURL:)` alone can't resolve relative `<link href>`/`<script
/// src>` references (there's no real base URL, the content is a fetched string, not a local
/// file) — so `resolveAsset` fetches same-folder assets first (from the server or, for
/// archive-internal HTML, from the same open archive — see the two call sites), writes
/// everything into one local directory, and loads via `loadFileURL` instead, which does
/// resolve relative paths against its neighbors on disk.
struct HTMLRenderedView: View {
    let cacheKey: String
    let html: String
    let resolveAsset: (String) async -> URL?

    @State private var localHTMLURL: URL?

    var body: some View {
        Group {
            if let localHTMLURL {
                HTMLWebView(fileURL: localHTMLURL, readAccessURL: localHTMLURL.deletingLastPathComponent())
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
            .appendingPathComponent("HTMLPreview", isDirectory: true)
            .appendingPathComponent(cacheKey.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Always `.html`, never `fileName`'s real extension: `loadFileURL` has WebKit infer
        // MIME type from the file's own extension, and the content written here is always
        // HTML — including for Markdown, converted upstream. Writing it out as e.g.
        // `README.md` made WebKit render the (correctly-converted) HTML *source* as plain
        // text instead of interpreting it as markup — looked like "just shown as code."
        let mainFileURL = directory.appendingPathComponent("index.html")
        guard (try? html.write(to: mainFileURL, atomically: true, encoding: .utf8)) != nil else { return }

        // The `href`/`src` regex scan walks the entire document; run it off the main thread so a
        // large HTML file doesn't stall the UI while its assets are being resolved.
        let html = html
        let assetPaths = await Task.detached(priority: .userInitiated) {
            Self.relativeAssetPaths(in: html)
        }.value
        for relativePath in assetPaths {
            guard let downloadedURL = await resolveAsset(relativePath) else { continue }
            // Root-absolute references (`/assets/app.js`) are resolved by `resolveAsset`
            // relative to the file's own folder too (there's no real site root to anchor
            // them to) — strip the leading slash to place them the same way on disk.
            let localRelativePath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
            guard let destinationURL = SafeDestination.within(directory, localRelativePath) else { continue }
            try? FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destinationURL)
            try? FileManager.default.copyItem(at: downloadedURL, to: destinationURL)
        }

        localHTMLURL = mainFileURL
    }

    /// Every `href="..."`/`src="..."` value that isn't already absolute (`http(s)://`,
    /// protocol-relative `//`, `data:`, `mailto:`) or an in-page anchor (`#section`) — the
    /// same-folder assets a fetched HTML string alone has no way to reach.
    private nonisolated static func relativeAssetPaths(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?:href|src)\s*=\s*["']([^"'#][^"']*)["']"#, options: [.caseInsensitive]) else {
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

/// Resolves a relative (or root-absolute) asset reference against a file's own containing
/// folder — shared by the server-backed and archive-backed `resolveAsset` closures so the
/// same path-joining logic (and the same root-absolute-becomes-folder-relative heuristic)
/// isn't duplicated between them.
enum RelativeAssetPath {
    /// - Parameters:
    ///   - relativePath: e.g. `"style.css"`, `"../shared/app.js"`, or `"/assets/app.js"`.
    ///   - directory: the referencing file's own parent directory (server path, or archive
    ///     folder path — same string shape either way: no leading slash, `""` for the root).
    /// - Returns: `(parent, name)` split of the resolved path, or `nil` if it resolves to
    ///   nothing sensible (e.g. an empty reference).
    static func resolve(_ relativePath: String, relativeTo directory: String) -> (parent: String, name: String)? {
        // Root-absolute references have no real site root to anchor to here — treat them as
        // relative to the file's own folder, the same heuristic a typical single-folder
        // static site upload effectively already assumes.
        let cleanedReference = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
        // `URL(fileURLWithPath:)` treats an empty path as the process's current working
        // directory, not "no base" — an empty `directory` (files at the volume root) needs an
        // explicit "/" base instead, or sibling paths silently resolve against the app's cwd.
        let baseURL = URL(fileURLWithPath: directory.isEmpty ? "/" : directory, isDirectory: true)
        let resolvedPath = URL(fileURLWithPath: cleanedReference, relativeTo: baseURL).standardizedFileURL.path
        let cleanPath = resolvedPath.hasPrefix("/") ? String(resolvedPath.dropFirst()) : resolvedPath
        guard !cleanPath.isEmpty else { return nil }
        let parent = (cleanPath as NSString).deletingLastPathComponent
        let name = (cleanPath as NSString).lastPathComponent
        guard !name.isEmpty else { return nil }
        return (parent, name)
    }
}

@MainActor
private struct HTMLWebView {
    let fileURL: URL
    let readAccessURL: URL

    fileprivate func makeWebView(coordinator: Coordinator) -> WKWebView {
        // The rendered content is an untrusted file from the user's server (or an archive).
        // JavaScript is disabled so a hostile page can't read neighbouring files off disk or
        // exfiltrate them; the navigation delegate pins navigation to the local file and
        // blocks every outbound request.
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        // No shared cookie/storage jar for untrusted server content — nothing to reach even if
        // the JS-off + navigation-blocked guarantees were somehow bypassed.
        configuration.websiteDataStore = .nonPersistent()
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
