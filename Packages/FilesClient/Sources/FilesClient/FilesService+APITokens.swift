import CoreModels
import Foundation
import NetworkClient

/// The API token routes of `backend/src/routes/auth.js`. They are reached with a session, never
/// with a token, and an installation without accounts issues none.
extension FilesService {
    func apiTokens(serverURL: URL) async throws -> [APIToken] {
        let url = serverURL.appendingPathComponent(APIPath.apiTokens)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: APITokensEnvelope.self).tokens
    }

    /// 201 with `{ token, secret }`. A wrong password is a 401 carrying a message; too many tokens
    /// or a bad name, scope or expiry is a 400 carrying one.
    func createAPIToken(serverURL: URL, name: String, scope: APIToken.Scope, expiresInDays: Int?, password: String?) async throws -> IssuedAPIToken {
        let url = serverURL.appendingPathComponent(APIPath.apiTokens)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(NewAPITokenBody(name: name, scope: scope, expiresInDays: expiresInDays, password: password))
        return try await decodeAccountResponse(sendAccountRequest(request), as: IssuedAPIToken.self)
    }

    func renameAPIToken(serverURL: URL, id: String, name: String) async throws -> APIToken {
        let url = serverURL.appendingPathComponent(APIPath.apiTokens).appendingPathComponent(id)
        var request = Self.makeRequest(url: url, method: .patch)
        request.setJSONContentType()
        request.httpBody = try Self.encode(NameBody(name: name))
        return try await decodeAccountResponse(sendAccountRequest(request), as: APITokenEnvelope.self).token
    }

    func revokeAPIToken(serverURL: URL, id: String) async throws {
        let url = serverURL.appendingPathComponent(APIPath.apiTokens).appendingPathComponent(id)
        let request = Self.makeRequest(url: url, method: .delete)
        _ = try await sendAccountRequest(request)
    }
}
