import CoreModels
import Dependencies
import Foundation
import Keychain
import NetworkClient

extension AuthClient {
    public static func live(
        networkClient: NetworkClient,
        keychainClient: KeychainClient,
        cookieStorage: HTTPCookieStorage
    ) -> AuthClient {
        let localAuthService = LocalAuthService(networkClient: networkClient)
        let cookieStore = SessionCookieStore(keychainClient: keychainClient, cookieStorage: cookieStorage)

        @Sendable
        func captureAndPersist(serverURL: URL, authMode: AuthMode, cookieName: String, username: String?) throws {
            guard let credentials = cookieStore.capture(
                serverURL: serverURL,
                authMode: authMode,
                cookieName: cookieName,
                username: username
            ) else {
                throw AuthClientError.sessionCookieMissing
            }
            do {
                try cookieStore.persist(credentials)
            } catch {
                throw AuthClientError.keychain(String(describing: error))
            }
        }

        return AuthClient(
            fetchStatus: { serverURL in
                try await localAuthService.status(serverURL: serverURL)
            },
            login: { serverURL, identifier, password in
                let user = try await localAuthService.login(serverURL: serverURL, identifier: identifier, password: password)
                try captureAndPersist(
                    serverURL: serverURL,
                    authMode: .local,
                    cookieName: AuthClientConfiguration.CookieName.local,
                    username: user.username
                )
                return user
            },
            me: { serverURL in
                try await localAuthService.me(serverURL: serverURL)
            },
            logout: { serverURL in
                try? await localAuthService.logout(serverURL: serverURL)
                cookieStore.clear(serverURL: serverURL)
            },
            restoreSession: {
                guard let credentials = cookieStore.loadPersisted() else { return nil }
                cookieStore.install(credentials)
                return credentials
            },
            clearSession: {
                cookieStore.clear(serverURL: nil)
            }
        )
    }
}

extension AuthClient: DependencyKey {
    public static var liveValue: AuthClient {
        @Dependency(\.networkClient) var networkClient
        @Dependency(\.keychainClient) var keychainClient
        @Dependency(\.cookieStorage) var cookieStorage
        return .live(networkClient: networkClient, keychainClient: keychainClient, cookieStorage: cookieStorage)
    }
}

extension DependencyValues {
    public var authClient: AuthClient {
        get { self[AuthClient.self] }
        set { self[AuthClient.self] = newValue }
    }
}
