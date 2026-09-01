import CoreModels
import Foundation
import NetworkClient

/// Plain JSON REST calls against NextExplorer's own session-cookie auth endpoints (`/api/auth/*`).
struct LocalAuthService: Sendable {
    let networkClient: NetworkClient

    func status(serverURL: URL) async throws -> AuthStatus {
        let request = try Self.makeRequest(serverURL: serverURL, path: AuthPath.status, method: .get)
        return try await send(request, decoding: AuthStatus.self)
    }

    func login(serverURL: URL, identifier: String, password: String) async throws -> User {
        var request = try Self.makeRequest(serverURL: serverURL, path: AuthPath.login, method: .post)
        request.setJSONContentType()
        do {
            request.httpBody = try JSONEncoder().encode(LoginRequestBody(email: identifier, password: password))
        } catch {
            throw AuthClientError.decoding(error.localizedDescription)
        }
        let envelope = try await send(request, decoding: UserEnvelope.self, unauthorizedError: .invalidCredentials)
        guard let user = envelope.user else {
            throw AuthClientError.invalidCredentials
        }
        return user
    }

    func me(serverURL: URL) async throws -> User {
        let request = try Self.makeRequest(serverURL: serverURL, path: AuthPath.me, method: .get)
        let envelope = try await send(request, decoding: UserEnvelope.self, unauthorizedError: .sessionExpired)
        guard let user = envelope.user else {
            throw AuthClientError.sessionExpired
        }
        return user
    }

    func logout(serverURL: URL) async throws {
        let request = try Self.makeRequest(serverURL: serverURL, path: AuthPath.logout, method: .post)
        _ = try await sendIgnoringBody(request)
    }

    private func send<Response: Decodable>(
        _ request: URLRequest,
        decoding type: Response.Type,
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
        } catch {
            throw AuthClientError.network(String(describing: error))
        }
    }

    private static func validate(_ response: HTTPURLResponse, unauthorizedError: AuthClientError) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw unauthorizedError
        case 429:
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
