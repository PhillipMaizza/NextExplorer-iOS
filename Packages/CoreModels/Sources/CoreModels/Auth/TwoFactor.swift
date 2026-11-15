import Foundation

/// `GET /api/auth/totp`: whether the signed in account asks for a code at sign in, and how many
/// recovery codes it has left (`twoFactorStatus` in `backend/src/services/users/twoFactor.js`).
public struct TwoFactorStatus: Codable, Equatable, Sendable {
    public let isEnabled: Bool
    /// A secret was drawn but never confirmed with a code, so the second factor is still off.
    public let isPending: Bool
    public let confirmedAt: String?
    public let recoveryCodesLeft: Int

    public init(isEnabled: Bool, isPending: Bool = false, confirmedAt: String? = nil, recoveryCodesLeft: Int = 0) {
        self.isEnabled = isEnabled
        self.isPending = isPending
        self.confirmedAt = confirmedAt
        self.recoveryCodesLeft = recoveryCodesLeft
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled = "enabled"
        case isPending = "pending"
        case confirmedAt
        case recoveryCodesLeft
    }
}

/// `POST /api/auth/totp/start`: the secret to put in an authenticator app, once, and the
/// `otpauth://` address that carries it (the content of the QR code).
public struct TwoFactorSetup: Codable, Equatable, Sendable {
    public let secret: String
    public let uri: String

    public init(secret: String, uri: String) {
        self.secret = secret
        self.uri = uri
    }
}
