public enum NetworkError: Error, Equatable, Sendable {
    case transport(String)
    case invalidResponse
}
