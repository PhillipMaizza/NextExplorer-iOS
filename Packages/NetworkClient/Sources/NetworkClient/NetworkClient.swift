import DependenciesMacros
import Foundation

@DependencyClient
public struct NetworkClient: Sendable {
    public var send: @Sendable (_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Uploads `bodyFileURL` as the request body, reporting fractional progress (0...1) as the
    /// bytes go out. The body file is streamed from disk, so its size does not translate into
    /// resident memory (the caller is responsible for what that file contains, and for its
    /// on disk cost). Session/cookie handling is the same as `send`.
    public var upload: @Sendable (
        _ request: URLRequest,
        _ bodyFileURL: URL,
        _ onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> (Data, HTTPURLResponse)
    /// Streams the response body straight to a temporary file on disk rather than buffering it
    /// in memory, and hands back that file's URL. The caller owns the returned file: move it
    /// where it belongs (or delete it) before the enclosing scope ends. Session/cookie
    /// handling is the same as `send`. Use for large payloads (previews, downloads, archives)
    /// where `send`'s in-memory `Data` would spike resident memory.
    public var download: @Sendable (_ request: URLRequest) async throws -> (URL, HTTPURLResponse)
    /// Same as `download`, but served by a separate session with a small per host connection
    /// cap, so a burst of these (PDF first page thumbnail fetches while browsing a folder)
    /// can never take slots from the main session's interactive pool. Cookie jar and server
    /// trust handling are shared with `download`.
    public var lowPriorityDownload: @Sendable (_ request: URLRequest) async throws -> (URL, HTTPURLResponse)
}
