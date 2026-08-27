import FilesClient
import Foundation

/// Runs a throwing async call and boxes the outcome, mapping anything that isn't already a
/// `FilesClientError` to `.network`. Replaces the `do { … } catch { … as? FilesClientError
/// ?? .network(String(describing:)) }` block that every reducer effect would otherwise
/// repeat verbatim.
///
///     return .run { send in
///         await send(.itemsResponse(await apiResult { try await filesClient.browse(url, path) }))
///     }
func apiResult<T>(_ operation: () async throws -> T) async -> Result<T, FilesClientError> {
    do {
        return .success(try await operation())
    } catch {
        return .failure((error as? FilesClientError) ?? .network(String(describing: error)))
    }
}
