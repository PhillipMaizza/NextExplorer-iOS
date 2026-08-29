import SwiftUI
import WebKit

/// Hosts a web-based office editor in a `WKWebView`. Two shapes:
///
/// * `.url` — load a fully-formed URL directly. Collabora's `urlSrc` already carries its
///   `WOPISrc` and `access_token`, so nothing else is needed.
/// * `.onlyOfficeShim` — ONLYOFFICE has no single URL; the host page must pull in the
///   Document Server's `api.js` and call `DocsAPI.DocEditor` with the signed config. That
///   tiny page is generated here and loaded with the Document Server as its base URL so the
///   script and its iframe are same-origin.
///
/// Neither editor authenticates against the app session cookie — the Document Server uses a
/// signed `backend` token baked into the config, and Collabora uses the WOPI `access_token`.
struct OfficeWebView: UIViewRepresentable {
    enum Load: Equatable {
        case url(URL)
        case onlyOfficeShim(documentServerURL: URL, configJSON: Data)
    }

    let load: Load

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.bounces = false

        apply(load, to: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedValue != load else { return }
        apply(load, to: webView, coordinator: context.coordinator)
    }

    private func apply(_ load: Load, to webView: WKWebView, coordinator: Coordinator) {
        coordinator.loadedValue = load
        switch load {
        case let .url(url):
            webView.load(URLRequest(url: url))
        case let .onlyOfficeShim(documentServerURL, configJSON):
            let config = String(decoding: configJSON, as: UTF8.self)
            webView.loadHTMLString(
                Self.onlyOfficeHTML(documentServerURL: documentServerURL, config: config),
                baseURL: documentServerURL
            )
        }
    }

    private static func onlyOfficeHTML(documentServerURL: URL, config: String) -> String {
        let apiScript = documentServerURL
            .appendingPathComponent("web-apps/apps/api/documents/api.js")
            .absoluteString
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>html, body, #placeholder { margin: 0; padding: 0; height: 100%; width: 100%; overflow: hidden; }</style>
        </head>
        <body>
        <div id="placeholder"></div>
        <script src="\(apiScript)"></script>
        <script>new DocsAPI.DocEditor("placeholder", \(config));</script>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKUIDelegate {
        var loadedValue: Load?

        /// `target="_blank"` links (the editor's help pages, share dialogs) have no window to
        /// open into inside a `WKWebView` unless we route them back to the main frame.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
