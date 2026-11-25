import CoreModels
import Foundation
import NetworkClient
import os

/// Plain JSON REST calls against NextExplorer's own session cookie auth endpoints (`/api/auth/*`).
struct LocalAuthService: Sendable {
    struct SignedIn: Sendable {
        let user: User
        let sessionCookies: [HTTPCookie]
    }

    let networkClient: NetworkClient
    private let secondFactorCookies = OSAllocatedUnfairLock<[HTTPCookie]>(initialState: [])

    func status(serverURL: URL) async throws -> AuthStatus {
        let request = try Self.makeRequest(serverURL: serverURL, path: AuthPath.status, method: .get)
        let (data, response) = try await performSend(request)
        try Self.validate(response, unauthorizedError: .sessionExpired)
        var status: AuthStatus
        do {
            status = try JSONDecoder().decode(AuthStatus.self, from: data)
        } catch {
            throw AuthClientError.decoding(error.localizedDescription)
        }
        status.isRedirectedToHTTPS = Self.isRedirectedToHTTPS(requested: serverURL, answered: response.url)
        if status.isRedirectedToHTTPS {
            status.redirectedPort = Self.answeredPort(response.url)
        }
        return status
    }

    private static let defaultHTTPSPort = 443

    /// The port to keep when the server answered from https: the one it answered on, or `nil` for
    /// the default, so a redirect from `http://host:8080` to `https://host` does not keep `:8080`.
    static func answeredPort(_ answered: URL?) -> Int? {
        guard let port = answered?.port, port != defaultHTTPSPort else { return nil }
        return port
    }

    static func isRedirectedToHTTPS(requested: URL, answered: URL?) -> Bool {
        guard let answered, requested.scheme?.lowercased() == "http", answered.scheme?.lowercased() == "https" else {
            return false
        }
        return requested.host()?.lowercased() == answered.host()?.lowercased()
    }

    func login(serverURL: URL, identifier: String, password: String) async throws -> SignedIn {
        var request = try Self.makeRequest(serverURL: serverURL, path: AuthPath.login, method: .post)
        request.setJSONContentType()
        do {
            request.httpBody = try JSONEncoder().encode(LoginRequestBody(
                emailOrUsername: identifier,
                password: password
            ))
        } catch {
            throw AuthClientError.decoding(error.localizedDescription)
        }
        let (envelope, cookies) = try await signInSend(
            request,
            serverURL: serverURL,
            unauthorizedError: .invalidCredentials
        )
        if envelope.isTOTPRequired == true {
            secondFactorCookies.withLock { $0 = cookies }
            throw AuthClientError.secondFactorRequired
        }
        guard let user = envelope.user else {
            throw AuthClientError.decoding("sign in response had no user")
        }
        return SignedIn(user: user, sessionCookies: cookies)
    }

    func loginTOTP(serverURL: URL, code: String) async throws -> SignedIn {
        var request = try Self.makeRequest(serverURL: serverURL, path: AuthPath.loginTOTP, method: .post)
        request.setJSONContentType()
        do {
            request.httpBody = try JSONEncoder().encode(TOTPRequestBody(code: code))
        } catch {
            throw AuthClientError.decoding(error.localizedDescription)
        }
        let pending = secondFactorCookies.withLock { $0 }
        Self.prepareSignIn(&request, sending: pending)
        let (data, response) = try await performSend(request)
        if response.statusCode == HTTPStatus.unauthorized {
            let errorCode = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error?.code
            throw errorCode == Self.invalidTOTPCode ? AuthClientError.invalidCode : AuthClientError.secondFactorExpired
        }
        try Self.validate(response, unauthorizedError: .secondFactorExpired)
        let envelope: UserEnvelope
        do {
            envelope = try JSONDecoder().decode(UserEnvelope.self, from: data)
        } catch {
            throw AuthClientError.decoding(error.localizedDescription)
        }
        guard let user = envelope.user else {
            throw AuthClientError.decoding("code response had no user")
        }
        secondFactorCookies.withLock { $0 = [] }
        let issued = Self.sessionCookies(in: response, for: serverURL)
        return SignedIn(user: user, sessionCookies: issued.isEmpty ? pending : issued)
    }

    func exchangeOIDC(serverURL: URL, code: String, codeVerifier: String) async throws -> SignedIn {
        var request = try Self.makeRequest(serverURL: serverURL, path: AuthPath.oidcExchange, method: .post)
        request.setJSONContentType()
        do {
            request.httpBody = try JSONEncoder().encode(
                OIDCExchangeRequestBody(code: code, code_verifier: codeVerifier)
            )
        } catch {
            throw AuthClientError.decoding(error.localizedDescription)
        }
        let (envelope, cookies) = try await signInSend(
            request,
            serverURL: serverURL,
            unauthorizedError: .oidcFailed("exchange rejected")
        )
        guard let user = envelope.user else {
            throw AuthClientError.oidcFailed("no user in exchange response")
        }
        return SignedIn(user: user, sessionCookies: cookies)
    }

    private func signInSend(
        _ request: URLRequest,
        serverURL: URL,
        unauthorizedError: AuthClientError
    ) async throws -> (UserEnvelope, [HTTPCookie]) {
        var request = request
        Self.prepareSignIn(&request, sending: [])
        let (data, response) = try await performSend(request)
        try Self.validate(response, unauthorizedError: unauthorizedError)
        let envelope: UserEnvelope
        do {
            envelope = try JSONDecoder().decode(UserEnvelope.self, from: data)
        } catch {
            throw AuthClientError.decoding(error.localizedDescription)
        }
        return (envelope, Self.sessionCookies(in: response, for: serverURL))
    }

    private static func prepareSignIn(_ request: inout URLRequest, sending cookies: [HTTPCookie]) {
        request.httpShouldHandleCookies = false
        for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }

    private static func sessionCookies(in response: HTTPURLResponse, for serverURL: URL) -> [HTTPCookie] {
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { fields, entry in
            if let name = entry.key as? String, let value = entry.value as? String {
                fields[name] = value
            }
        }
        return HTTPCookie.cookies(withResponseHeaderFields: fields, for: serverURL)
    }

    func me(serverURL: URL) async throws -> User {
        let request = try Self.makeRequest(serverURL: serverURL, path: AuthPath.me, method: .get)
        let envelope = try await send(request, decoding: UserEnvelope.self, unauthorizedError: .sessionExpired)
        guard let user = envelope.user else {
            throw AuthClientError.sessionExpired
        }
        return user
    }

    /// With `credentials`, logs out that account even while another one is active: its own cookie
    /// is sent and the shared jar is neither read nor changed by the reply.
    func logout(serverURL: URL, credentials: SessionCredentials? = nil) async throws {
        var request = try Self.makeRequest(serverURL: serverURL, path: AuthPath.logout, method: .post)
        if let credentials {
            request.httpShouldHandleCookies = false
            request.setValue(credentials.cookieHeader, forHTTPHeaderField: HTTPHeaderField.cookie)
        }
        _ = try await sendIgnoringBody(request)
    }

    private func send<Response: Decodable>(
        _ request: URLRequest,
        decoding _: Response.Type,
        unauthorizedError: AuthClientError = .sessionExpired
    ) async throws -> Response {
        let (data, response) = try await performSend(request)
        try Self.validate(response, unauthorizedError: unauthorizedError)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AuthClientError.decoding(error.localizedDescription)
        }
    }

    private func sendIgnoringBody(_ request: URLRequest) async throws -> HTTPURLResponse {
        let (_, response) = try await performSend(request)
        try Self.validate(response, unauthorizedError: .sessionExpired)
        return response
    }

    private func performSend(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await networkClient.send(request)
        } catch NetworkError.clientCertificateRequired {
            throw AuthClientError.clientCertificateRequired
        } catch NetworkError.clientCertificateRejected {
            throw AuthClientError.clientCertificateRejected
        } catch {
            throw AuthClientError.network(String(describing: error))
        }
    }

    private static func validate(_ response: HTTPURLResponse, unauthorizedError: AuthClientError) throws {
        switch response.statusCode {
        case HTTPStatus.success:
            return
        case HTTPStatus.unauthorized:
            throw unauthorizedError
        case HTTPStatus.tooManyRequests:
            throw AuthClientError.rateLimited
        default:
            throw AuthClientError.server(statusCode: response.statusCode)
        }
    }

    private static func makeRequest(serverURL: URL, path: String, method: HTTPMethod) throws -> URLRequest {
        let url = serverURL.appendingPathComponent(path)
        var request = URLRequest(url: url, method: method)
        request.setValue(MIMEType.json, forHTTPHeaderField: HTTPHeaderField.accept)
        return request
    }
}
