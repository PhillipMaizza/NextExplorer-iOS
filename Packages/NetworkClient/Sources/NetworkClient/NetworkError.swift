import Foundation

public enum NetworkError: Error, Equatable, Sendable {
    case transport(String)
    /// The device has no usable route to the server: no connectivity, the host is
    /// unreachable, or the request timed out before any response. Distinct from `.transport`
    /// so callers can fall back to cached content rather than surfacing a generic failure.
    case offline
    case invalidResponse
    /// The response body exceeded `NetworkClient.maxInMemoryResponseBytes` — refused before it
    /// could be fully buffered, so a hostile or misbehaving server can't drive the app out of
    /// memory through the in-memory `send` path. Large payloads must go through `download`.
    case responseTooLarge
}

extension NetworkError {
    /// Classifies a raw error thrown by `URLSession`: connectivity failures become `.offline`,
    /// everything else keeps its description as `.transport`.
    static func from(_ error: Error) -> NetworkError {
        if let urlError = error as? URLError, offlineCodes.contains(urlError.code) {
            return .offline
        }
        return .transport(error.localizedDescription)
    }

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
