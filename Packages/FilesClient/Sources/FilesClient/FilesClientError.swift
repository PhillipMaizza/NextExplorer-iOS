public enum FilesClientError: Error, Equatable, Sendable {
    case sessionExpired
    case network(String)
    case decoding(String)
    case server(statusCode: Int)
    case rateLimited
}
