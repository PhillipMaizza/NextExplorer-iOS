import CoreModels
import Dependencies
import Foundation
import Keychain
import NetworkClient

public extension AuthClient {
    static func live(
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
            loginOIDC: { serverURL in
                let pkce = PKCE.generate()
                var components = URLComponents(
                    url: serverURL.appendingPathComponent(AuthPath.oidcMobileLogin),
                    resolvingAgainstBaseURL: false
                )
                components?.queryItems = [
                    URLQueryItem(name: "code_challenge", value: pkce.challenge),
                    URLQueryItem(name: "code_challenge_method", value: "S256"),
                ]
                guard let authURL = components?.url else {
                    throw AuthClientError.oidcFailed("could not build authorization URL")
                }

                let authenticator = await OIDCWebAuthenticator()
                let callbackURL = try await authenticator.authenticate(
                    url: authURL,
                    callbackURLScheme: AuthClientConfiguration.oidcCallbackScheme
                )

                let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
                if let serverError = items.first(where: { $0.name == "error" })?.value {
                    throw AuthClientError.oidcFailed(serverError)
                }
                guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                    throw AuthClientError.oidcFailed("callback missing code")
                }

                let user = try await localAuthService.exchangeOIDC(
                    serverURL: serverURL,
                    code: code,
                    codeVerifier: pkce.verifier
                )
                // The bridge issues a normal local session cookie, so capture it exactly as the
                // password path does — just tagged `.oidc` for provenance.
                try captureAndPersist(
                    serverURL: serverURL,
                    authMode: .oidc,
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
            },
            restoreSession: {
                guard let credentials = cookieStore.activeCredentials() else { return nil }
                cookieStore.install(credentials)
                return credentials
            },
            listSessions: {
                cookieStore.allSessions()
            },
            activeAccountID: {
                cookieStore.activeCredentials()?.accountID
            },
            switchAccount: { accountID in
                cookieStore.setActive(id: accountID)
            },
            removeAccount: { accountID in
                // Best-effort server logout of the account being removed, then drop it locally.
                if let serverURL = cookieStore.allSessions().first(where: { $0.accountID == accountID })?.serverBaseURL {
                    try? await localAuthService.logout(serverURL: serverURL)
                }
                return cookieStore.remove(id: accountID)
            },
            clearActiveSession: {
                cookieStore.clearActive()
            },
            clearAllSessions: {
                cookieStore.clearAll()
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

public extension DependencyValues {
    var authClient: AuthClient {
        get { self[AuthClient.self] }
        set { self[AuthClient.self] = newValue }
    }
}
