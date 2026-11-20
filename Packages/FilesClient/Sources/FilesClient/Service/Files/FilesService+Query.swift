import Foundation

extension FilesService {
    /// Query values are encoded with only the unreserved characters left alone, so a search
    /// holding `&`, `+` or `#` stays one value.
    private static let unreservedQueryCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// The address of `path` under the server with `items` as its query, in the order given.
    static func url(serverURL: URL, path: String, items: [(String, String)]) throws -> URL {
        try url(serverURL.appendingPathComponent(path), items: items)
    }

    /// `base` with the query items added, encoded as above.
    static func url(_ base: URL, items: [(String, String)]) throws -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        // No items means no query at all, not a bare `?`.
        components?.percentEncodedQueryItems = items.isEmpty
            ? nil
            : items.map { name, value in
                URLQueryItem(
                    name: name,
                    value: value.addingPercentEncoding(withAllowedCharacters: unreservedQueryCharacters)
                )
            }
        guard let url = components?.url else {
            throw FilesClientError.decoding("Could not build the request URL.")
        }
        return url
    }

    /// One path segment, encoded so an id holding a slash cannot point at another route.
    static func encodedSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreservedQueryCharacters) ?? value
    }
}
