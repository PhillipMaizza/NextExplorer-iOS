import DependenciesMacros
import Foundation

@DependencyClient
public struct NetworkClient: Sendable {
    public var send: @Sendable (_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Uploads `bodyFileURL` as the request body, reporting fractional progress (0...1) as the
    /// bytes go out. Streams from disk rather than buffering, so a multi-gigabyte upload never
    /// sits in memory. Session/cookie handling is the same as `send`.
    public var upload: @Sendable (
        _ request: URLRequest,
        _ bodyFileURL: URL,
        _ onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> (Data, HTTPURLResponse)
}
