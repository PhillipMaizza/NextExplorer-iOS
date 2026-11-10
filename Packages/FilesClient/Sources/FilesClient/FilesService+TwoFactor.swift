import CoreModels
import Foundation
import NetworkClient

/// The second factor routes of `backend/src/routes/auth.js`. Turning it on needs a session that was
/// opened with the password (403 otherwise, with a message); changing it afterwards asks for the
/// password again.
extension FilesService {
    func twoFactorStatus(serverURL: URL) async throws -> TwoFactorStatus {
        let url = serverURL.appendingPathComponent(APIPath.twoFactor)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: TwoFactorStatus.self)
    }

    /// `POST /api/auth/totp/start`: draws a secret and turns nothing on. 409 when it is already on.
    func beginTwoFactorSetup(serverURL: URL) async throws -> TwoFactorSetup {
        let url = serverURL.appendingPathComponent(APIPath.twoFactorStart)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        request.httpBody = Data("{}".utf8)
        return try await decodeAccountResponse(sendAccountRequest(request), as: TwoFactorSetup.self)
    }

    /// `POST /api/auth/totp/confirm`: turns it on once the code proves the phone holds the secret.
    /// A wrong code is a 401 carrying a message. Answers the first set of recovery codes.
    func confirmTwoFactorSetup(serverURL: URL, code: String) async throws -> [String] {
        let url = serverURL.appendingPathComponent(APIPath.twoFactorConfirm)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(TwoFactorCodeBody(code: code))
        return try await decodeAccountResponse(sendAccountRequest(request), as: RecoveryCodesEnvelope.self).recoveryCodes
    }

    /// `POST /api/auth/totp/recovery-codes`: new codes, the old ones stop working. Needs the password.
    func replaceRecoveryCodes(serverURL: URL, password: String) async throws -> [String] {
        let url = serverURL.appendingPathComponent(APIPath.twoFactorRecoveryCodes)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(PasswordBody(password: password))
        return try await decodeAccountResponse(sendAccountRequest(request), as: RecoveryCodesEnvelope.self).recoveryCodes
    }

    /// `DELETE /api/auth/totp` with the password in the body: 204 when it is off.
    func disableTwoFactor(serverURL: URL, password: String) async throws {
        let url = serverURL.appendingPathComponent(APIPath.twoFactor)
        var request = Self.makeRequest(url: url, method: .delete)
        request.setJSONContentType()
        request.httpBody = try Self.encode(PasswordBody(password: password))
        _ = try await sendAccountRequest(request)
    }

    func decodeAccountResponse<Response: Decodable>(_ data: Data, as _: Response.Type) throws -> Response {
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
    }
}
