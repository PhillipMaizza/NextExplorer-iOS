import Foundation
import TestUtils

enum NetworkClientFixture: String, FixtureFile {
    static let bundle = Bundle.module

    // MARK: response

    case responseErrorNameRequired = "response/error-name-required"
    case responseOkTrue = "response/ok-true"

    // MARK: mutual TLS identities

    case certificateAuthority = "ca"
    case clientIdentity = "client"
    case clientLegacyIdentity = "client-legacy"
    case rogueClientIdentity = "rogue-client"
    case serverIdentity = "server"

    var fileExtension: String {
        switch self {
        case .certificateAuthority:
            "der"
        case .clientIdentity, .clientLegacyIdentity, .rogueClientIdentity, .serverIdentity:
            "p12"
        case .responseErrorNameRequired, .responseOkTrue:
            "json"
        }
    }
}
