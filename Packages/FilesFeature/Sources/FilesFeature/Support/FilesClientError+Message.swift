import FilesClient
import Localization

extension FilesClientError {
    var userMessage: String {
        switch self {
        case .sessionExpired: L10n.Error.sessionExpired
        case let .forbidden(message): message ?? L10n.Error.forbidden
        case .rateLimited: L10n.Error.rateLimited
        case .network: L10n.Error.network
        case .offline: L10n.Error.offline
        case .timedOut: L10n.Error.timedOut
        case .changedOnServer: L10n.Error.changedOnServer
        case .decoding: L10n.Error.decoding
        case let .server(statusCode): L10n.Error.server(statusCode)
        case let .serverMessage(_, message): message
        case .clientCertificateRequired: L10n.Error.clientCertificateRequired
        case .clientCertificateRejected: L10n.Error.clientCertificateRejected
        }
    }
}
