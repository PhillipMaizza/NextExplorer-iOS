import Dependencies
import Foundation

public extension HTTPCookieStorage {
    static let appSession: HTTPCookieStorage = URLSessionConfiguration.ephemeral.httpCookieStorage ?? .shared
}

private enum HTTPCookieStorageKey: DependencyKey {
    static let liveValue: HTTPCookieStorage = .appSession
    static let testValue: HTTPCookieStorage = .shared
}

public extension DependencyValues {
    var cookieStorage: HTTPCookieStorage {
        get { self[HTTPCookieStorageKey.self] }
        set { self[HTTPCookieStorageKey.self] = newValue }
    }
}
