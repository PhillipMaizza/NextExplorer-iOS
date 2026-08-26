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
}
