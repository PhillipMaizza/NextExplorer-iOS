import ComposableArchitecture
import FilesClient
import Foundation

public enum SessionExpiry {
    /// Flipped to `true` by `apiResult` the moment an authenticated endpoint answers 401
    /// (`FilesClientError.sessionExpired`). `AppFeature` watches it, drops back to the login
    /// screen and clears the session, then resets it. A process-wide in-memory flag rather
    /// than delegate plumbing through every feature — every reducer effect already funnels
    /// its errors through `apiResult`.
    public static let sharedKey = "sessionDidExpire"
}

/// Runs a throwing async call and boxes the outcome, mapping anything that isn't already a
/// `FilesClientError` to `.network`. Replaces the `do { … } catch { … as? FilesClientError
/// ?? .network(String(describing:)) }` block that every reducer effect would otherwise
/// repeat verbatim. A `.sessionExpired` (401) additionally trips `SessionExpiry`.
///
///     return .run { send in
///         await send(.itemsResponse(await apiResult { try await filesClient.browse(url, path) }))
///     }
func apiResult<T>(_ operation: () async throws -> T) async -> Result<T, FilesClientError> {
    do {
        return .success(try await operation())
    } catch {
        let filesError = (error as? FilesClientError) ?? .network(String(describing: error))
        if filesError == .sessionExpired {
            @Shared(.inMemory(SessionExpiry.sharedKey)) var sessionDidExpire = false
            $sessionDidExpire.withLock { $0 = true }
        }
        return .failure(filesError)
    }
}
