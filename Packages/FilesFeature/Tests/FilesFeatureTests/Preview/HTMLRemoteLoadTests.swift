@testable import FilesFeature
import Foundation
import Testing
import TestUtils
import WebKit

/// A rendered page is an untrusted file: with the preview's configuration none of its images or
/// stylesheets may reach a host. Remote loads are stood in for by a scheme the test answers itself,
/// so the check needs no network; the control render proves the page really asks for them.
@MainActor
struct HTMLRemoteLoadTests {
    private enum Constants {
        static let scheme = "probe"
        static let pageName = "index.html"
        static let directoryPrefix = "html-remote-"
        static let page = """
        <html><head><link rel="stylesheet" href="probe://tracker.example/style.css"></head>
        <body><img src="probe://tracker.example/pixel.png"><p>Hello</p></body></html>
        """
    }

    /// Records every request the page makes to the probe scheme and fails it at once.
    @MainActor
    private final class ProbeHandler: NSObject, WKURLSchemeHandler {
        private(set) var requested: [URL] = []

        func webView(_: WKWebView, start task: any WKURLSchemeTask) {
            if let url = task.request.url {
                requested.append(url)
            }
            task.didFailWithError(URLError(.cannotConnectToHost))
        }

        func webView(_: WKWebView, stop _: any WKURLSchemeTask) {}
    }

    /// Resumes once the page has finished loading, its subresources included, or failed to.
    @MainActor
    private final class LoadWaiter: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isFinished = false
        /// Only a page that loaded proves the rules let local content through.
        private(set) var didLoad = false

        func wait() async {
            guard !isFinished else { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            didLoad = true
            finish()
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError _: any Error) {
            finish()
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: any Error) {
            finish()
        }

        private func finish() {
            isFinished = true
            continuation?.resume()
            continuation = nil
        }
    }

    /// Loads the page from disk with `configuration`: whether it loaded, and what it asked the probe for.
    private func render(
        _ configuration: WKWebViewConfiguration
    ) async throws -> (didLoad: Bool, remoteRequests: [URL]) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Constants.directoryPrefix)\(TestID.name())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pageURL = directory.appendingPathComponent(Constants.pageName)
        try Constants.page.write(to: pageURL, atomically: true, encoding: .utf8)

        let probe = ProbeHandler()
        configuration.setURLSchemeHandler(probe, forURLScheme: Constants.scheme)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let waiter = LoadWaiter()
        webView.navigationDelegate = waiter
        webView.loadFileURL(pageURL, allowingReadAccessTo: directory)
        await waiter.wait()
        return (waiter.didLoad, probe.requested)
    }

    @Test("Without the rules the page does ask for its remote image and stylesheet")
    func controlRenderReachesTheProbe() async throws {
        let result = try await render(WKWebViewConfiguration())

        #expect(result.didLoad)
        #expect(!result.remoteRequests.isEmpty)
    }

    @Test("With the preview's configuration the page loads and reaches no host at all")
    func previewRenderReachesNothing() async throws {
        let rules = try #require(await LocalOnlyContentRules.compiled())

        let result = try await render(LocalOnlyContentRules.webViewConfiguration(applying: rules))

        #expect(result.didLoad, "the rules must never block the local page itself")
        #expect(result.remoteRequests.isEmpty)
    }
}
