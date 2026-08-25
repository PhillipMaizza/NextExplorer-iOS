public enum AuthError: Error, Equatable, Sendable {
    case invalidServerURL
    case invalidCredentials
    case sessionExpired
    case ssoCancelled
    case ssoCallbackMissingSession
    case network(String)
    case decoding(String)
    case server(statusCode: Int, message: String?)
}
