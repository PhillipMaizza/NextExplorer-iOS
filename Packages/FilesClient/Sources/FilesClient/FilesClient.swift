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
    public var volumes: @Sendable (_ serverURL: URL) async throws -> [Volume]
    public var fetchPreferences: @Sendable (_ serverURL: URL) async throws -> UserPreferences
    public var updatePreference: @Sendable (
        _ serverURL: URL, _ key: UserPreferenceKey, _ value: Bool
    ) async throws -> Void
}
