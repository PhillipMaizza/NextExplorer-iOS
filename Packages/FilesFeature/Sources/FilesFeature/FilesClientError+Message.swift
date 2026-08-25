import FilesClient

extension FilesClientError {
    var userMessage: String {
        switch self {
        case .sessionExpired: "Your session expired. Sign in again."
        case .rateLimited: "Too many requests. Try again shortly."
        case .network: "Couldn't reach the server."
        case .decoding: "Server responded unexpectedly."
        case let .server(statusCode): "Server error (\(statusCode))."
        }
    }
}
