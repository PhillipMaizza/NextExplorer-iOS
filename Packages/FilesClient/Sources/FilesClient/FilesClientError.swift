public enum FilesClientError: Error, Equatable, Sendable {
    case sessionExpired
    case network(String)
    case decoding(String)
    case server(statusCode: Int)
    /// A non-2xx response whose body carried a human-readable message worth surfacing
    /// verbatim (admin user-management endpoints: "Cannot remove the last admin.", etc.).
    case serverMessage(statusCode: Int, message: String)
    case rateLimited
}
