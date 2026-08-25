import Dependencies
import Foundation

private enum HTTPCookieStorageKey: DependencyKey {
    static let liveValue: HTTPCookieStorage = .shared
    static let testValue: HTTPCookieStorage = .shared
}

extension DependencyValues {
    public var cookieStorage: HTTPCookieStorage {
        get { self[HTTPCookieStorageKey.self] }
        set { self[HTTPCookieStorageKey.self] = newValue }
    }
}
