import Foundation

public enum NetworkError: Error, Equatable, Sendable {
    case transport(String)
    /// The device has no usable route to the server: no connectivity, the host is
    /// unreachable, or the request timed out before any response. Distinct from `.transport`
    /// so callers can fall back to cached content rather than surfacing a generic failure.
    case offline
    case invalidResponse
    /// The response body exceeded `NetworkClient.maxInMemoryResponseBytes`: refused before it
    /// could be fully buffered, so a hostile or misbehaving server can't drive the app out of
    /// memory through the in-memory `send` path. Large payloads must go through `download`.
    case responseTooLarge
    /// The server (usually its reverse proxy) asked for a TLS client certificate and none is
    /// installed for it. Never `.offline`: the server is reachable, it just refuses the app.
    case clientCertificateRequired
    /// A client certificate was presented and the server refused it (untrusted issuer,
    /// expired, revoked).
    case clientCertificateRejected
}

extension NetworkError {
    /// Classifies a raw error thrown by `URLSession`: connectivity failures become `.offline`,
    /// a handshake the server ended over the client certificate becomes one of the certificate
    /// cases, and everything else keeps its description as `.transport`.
    static func from(
        _ error: Error,
        url: URL? = nil,
        certificates: ClientCertificateChallengeHandler? = nil
    ) -> NetworkError {
        guard let urlError = error as? URLError else {
            return .transport(error.localizedDescription)
        }
        switch urlError.code {
        case .clientCertificateRequired:
            return .clientCertificateRequired
        case .clientCertificateRejected:
            return .clientCertificateRejected
        default:
            break
        }
        if certificateDropCodes.contains(urlError.code), let outcome = certificates?.recentOutcome(for: url ?? urlError.failingURL) {
            return outcome == .missing ? .clientCertificateRequired : .clientCertificateRejected
        }
        if offlineCodes.contains(urlError.code) {
            return .offline
        }
        return .transport(error.localizedDescription)
    }

    private static let certificateDropCodes: Set<URLError.Code> = [
        .networkConnectionLost,
        .secureConnectionFailed,
    ]

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .networkConnectionLost,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
        .timedOut,
        .dataNotAllowed,
        .internationalRoamingOff,
    ]
}
