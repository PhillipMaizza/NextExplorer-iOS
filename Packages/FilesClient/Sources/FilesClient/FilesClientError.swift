public enum FilesClientError: Error, Equatable, Sendable {
    case sessionExpired
    /// HTTP 403 — the session is valid but the account lacks the right (non admin, non root,
    /// no write access, access rule). Carries the server's reason when it sent one.
    case forbidden(message: String?)
    case network(String)
    case decoding(String)
    case server(statusCode: Int)
    /// A non 2xx response whose body carried a human readable message worth surfacing
    /// verbatim (admin user management endpoints: "Cannot remove the last admin.", etc.).
    case serverMessage(statusCode: Int, message: String)
    case rateLimited
}
