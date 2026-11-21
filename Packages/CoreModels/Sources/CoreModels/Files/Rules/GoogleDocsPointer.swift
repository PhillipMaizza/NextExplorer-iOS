import Foundation

/// The small JSON stub files Google Drive's desktop sync writes in place of a native Google
/// Docs / Sheets / Slides document: `{"url": "https://docs.google.com/…", "resource_id": …}`.
/// Tapping one should send the user out to that URL (the Google app if installed, otherwise
/// the browser), not render the JSON in the text viewer.
public enum GoogleDocsPointer {
    /// Extensions Drive uses for these stubs. Every one is a small UTF-8 JSON file with a
    /// top level `url`.
    public static let extensions: Set<String> = [
        "gdoc", "gsheet", "gslides", "gdraw", "gform", "gtable", "gmap", "gsite", "gjam", "glink",
    ]

    public static func isPointerKind(_ kind: String) -> Bool {
        extensions.contains(kind.lowercased())
    }

    /// The link a stub file points at, or `nil` if the contents don't parse or the `url` isn't
    /// Google over https: the caller then falls back to showing the file as text. The stub sits on
    /// a server others can write to, so a link elsewhere could open a lookalike sign in page.
    public static func targetURL(fromContents contents: String) -> URL? {
        guard let data = contents.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["url"] as? String,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              let host = url.host()?.lowercased(),
              host == googleHost || host.hasSuffix("." + googleHost)
        else { return nil }
        return url
    }

    private static let googleHost = "google.com"
}
