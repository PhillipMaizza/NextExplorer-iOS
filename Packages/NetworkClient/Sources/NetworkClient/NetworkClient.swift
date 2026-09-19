import DependenciesMacros
import Foundation

@DependencyClient
public struct NetworkClient: Sendable {
    public var send: @Sendable (_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Same as `send` (in memory response), but served by the separate low priority session
    /// with a small per host connection cap, so a burst of these (background directory
    /// prefetch while browsing) can never take slots from the main session's interactive
    /// pool. Cookie jar and server trust handling are shared with `send`.
    public var lowPrioritySend: @Sendable (_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
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
    /// Same as `download`, but reports fractional receive progress (0...1) as the body streams to
    /// disk, so a long transfer (a large offline download) drives a live progress bar. Progress is
    /// throttled inside the URLSession delegate (a cheap time check on the serial delegate queue), so
    /// the callback fires only a few times a second and never backs the delegate queue up or slows the
    /// transfer. `onProgress` is not called when the server sends no `Content-Length`. Session, cookie
    /// and server trust handling are the same as `download`.
    public var downloadWithProgress: @Sendable (
        _ request: URLRequest,
        _ onProgress: @Sendable @escaping (_ fraction: Double) -> Void
    ) async throws -> (URL, HTTPURLResponse)
    /// Same as `download`, but served by a separate session with a small per host connection
    /// cap, so a burst of these (PDF first page thumbnail fetches while browsing a folder)
    /// can never take slots from the main session's interactive pool. Cookie jar and server
    /// trust handling are shared with `download`.
    public var lowPriorityDownload: @Sendable (_ request: URLRequest) async throws -> (URL, HTTPURLResponse)
    /// Drops the download session's pooled (keep alive) connections so the next download opens a fresh
    /// socket. Call before a batch after the session may have sat idle: a server or NAT silently drops
    /// an idle keep alive connection, but URLSession keeps reusing it and the next transfer stalls on
    /// the dead socket until it times out. Flushing first avoids that stall entirely.
    public var flushDownloadConnections: @Sendable () async -> Void
}
