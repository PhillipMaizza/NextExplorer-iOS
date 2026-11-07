public enum FilesClientError: Error, Equatable, Sendable {
    case sessionExpired
    /// HTTP 403: the session is valid but the account lacks the right (non admin, non root,
    /// no write access, access rule). Carries the server's reason when it sent one.
    case forbidden(message: String?)
    case network(String)
    /// No usable connection to the server (offline, host unreachable, or timed out before any
    /// response). Callers that hold a cached copy should serve it instead of surfacing this.
    case offline
    /// A mutation or upload got no answer within its budget. The server may still have done the
    /// work, so callers refetch rather than assume it failed.
    case timedOut
    /// A text file was changed on the server after the editor opened it, so saving now would
    /// silently replace those changes.
    case changedOnServer
    case decoding(String)
    case server(statusCode: Int)
    /// A non 2xx response whose body carried a human readable message worth surfacing
    /// verbatim (admin user management endpoints: "Cannot remove the last admin.", etc.).
    case serverMessage(statusCode: Int, message: String)
    case rateLimited
    /// The server demands a TLS client certificate and none is installed for it.
    case clientCertificateRequired
    /// The installed client certificate was refused by the server.
    case clientCertificateRejected
}
