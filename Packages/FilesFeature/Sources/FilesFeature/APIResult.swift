import ComposableArchitecture
import FilesClient
import Foundation

public enum SessionExpiry {
    /// Set to `true` by `apiResult` when an authenticated endpoint answers 401. `AppFeature`
    /// watches it, drops to the login screen, clears the session, then resets the flag. An
    /// in memory flag rather than delegate plumbing, since every effect already routes its
    /// errors through `apiResult`.
    public static let sharedKey = "sessionDidExpire"
}

/// Runs a throwing async call and boxes the outcome, mapping anything that isn't already a
/// `FilesClientError` to `.network`. Replaces the per effect `do/catch` that would otherwise
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
