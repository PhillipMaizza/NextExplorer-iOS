import Foundation

extension FilesService {
    /// Query values are encoded with only the unreserved characters left alone, so a search
    /// holding `&`, `+` or `#` stays one value.
    private static let unreservedQueryCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// The address of `path` under the server with `items` as its query, in the order given.
    static func url(serverURL: URL, path: String, items: [(String, String)]) throws -> URL {
        var components = URLComponents(url: serverURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.percentEncodedQueryItems = items.map { name, value in
            URLQueryItem(name: name, value: value.addingPercentEncoding(withAllowedCharacters: unreservedQueryCharacters))
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
