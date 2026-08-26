import CoreModels
import DependenciesMacros
import Foundation

@DependencyClient
public struct FilesClient: Sendable {
    public var browse: @Sendable (_ serverURL: URL, _ path: String) async throws -> BrowseResult
    public var search: @Sendable (
        _ serverURL: URL, _ path: String, _ query: String, _ limit: Int?
    ) async throws -> [SearchResultItem]
    public var favorites: @Sendable (_ serverURL: URL) async throws -> [Favorite]
    public var addFavorite: @Sendable (_ serverURL: URL, _ path: String) async throws -> Favorite
    public var removeFavorite: @Sendable (_ serverURL: URL, _ path: String) async throws -> Void
    public var volumes: @Sendable (_ serverURL: URL) async throws -> [Volume]
    public var fetchPreferences: @Sendable (_ serverURL: URL) async throws -> UserPreferences
    public var updatePreference: @Sendable (
        _ serverURL: URL, _ key: UserPreferenceKey, _ value: Bool
    ) async throws -> Void
    public var renameItem: @Sendable (
        _ serverURL: URL, _ item: FileItem, _ newName: String
    ) async throws -> FileItem
    public var deleteItems: @Sendable (_ serverURL: URL, _ items: [FileItem]) async throws -> Void
    public var fetchMetadata: @Sendable (_ serverURL: URL, _ path: String) async throws -> FileMetadata
    public var thumbnailURL: @Sendable (_ serverURL: URL, _ path: String) async throws -> URL?
    public var previewFile: @Sendable (_ serverURL: URL, _ item: FileItem) async throws -> URL
    public var fetchTextContent: @Sendable (_ serverURL: URL, _ path: String) async throws -> String
    public var saveTextContent: @Sendable (_ serverURL: URL, _ path: String, _ content: String) async throws -> Void
    public var extractZip: @Sendable (_ serverURL: URL, _ item: FileItem) async throws -> FileItem
    public var downloadRawFile: @Sendable (_ serverURL: URL, _ item: FileItem) async throws -> URL
    public var compressItem: @Sendable (_ serverURL: URL, _ item: FileItem) async throws -> FileItem
}

extension FilesClient {
    /// The same `GET /api/preview?path=...` URL `previewFile` downloads, exposed as a plain
    /// synchronous URL for streamable media (video/audio): `AVPlayer` can play it directly,
    /// using the server's existing HTTP Range support for seeking, without buffering the
    /// whole file into memory first the way a full download would.
    public static func previewURL(serverURL: URL, item: FileItem) -> URL? {
        var components = URLComponents(url: serverURL.appendingPathComponent("api/preview"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "path", value: item.id)]
        return components?.url
    }
}
