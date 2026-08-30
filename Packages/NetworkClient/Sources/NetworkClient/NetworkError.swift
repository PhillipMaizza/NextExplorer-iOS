public enum NetworkError: Error, Equatable, Sendable {
    case transport(String)
    case invalidResponse
    /// The response body exceeded `NetworkClient.maxInMemoryResponseBytes` — refused before it
    /// could be fully buffered, so a hostile or misbehaving server can't drive the app out of
    /// memory through the in-memory `send` path. Large payloads must go through `download`.
    case responseTooLarge
}
