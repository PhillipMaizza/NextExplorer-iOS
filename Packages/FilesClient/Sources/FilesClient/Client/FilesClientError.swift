import NetworkClient

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
    case archivePasswordRequired
    case archiveInvalidPassword
}

/// The server is still making a thumbnail (it answered 202 with `pending`), so there is neither a
/// thumbnail yet nor a verdict that there will be none.
public struct ThumbnailPendingError: Error, Equatable, Sendable {
    /// How long the server asked to wait before asking again, when it said.
    public let retryAfter: Duration?

    public init(retryAfter: Duration? = nil) {
        self.retryAfter = retryAfter
    }
}

public extension FilesClientError {
    var statusCode: Int? {
        switch self {
        case let .server(statusCode), let .serverMessage(statusCode, _): statusCode
        default: nil
        }
    }

    var isBadRequest: Bool {
        statusCode == HTTPStatus.badRequest.rawValue
    }
}

extension FilesClientError {
    /// The server or a proxy in front of it refused the request for its size (413).
    var isPayloadTooLarge: Bool {
        statusCode.map { $0 == HTTPStatus.payloadTooLarge } ?? false
    }
}
