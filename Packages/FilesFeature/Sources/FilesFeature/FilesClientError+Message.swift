import FilesClient
import Localization

extension FilesClientError {
    var userMessage: String {
        switch self {
        case .sessionExpired: L10n.Error.sessionExpired
        case let .forbidden(message): message ?? L10n.Error.forbidden
        case .rateLimited: L10n.Error.rateLimited
        case .network: L10n.Error.network
        case .decoding: L10n.Error.decoding
        case let .server(statusCode): L10n.Error.server(statusCode)
        case let .serverMessage(_, message): message
        }
    }
}
