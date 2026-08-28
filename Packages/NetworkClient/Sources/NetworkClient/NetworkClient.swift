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
}
