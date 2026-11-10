import CoreModels
import Foundation

/// Wire types for the admin user/volume endpoints. See `FilesService+Admin.swift`.
extension FilesService {
    struct UsersEnvelope: Decodable { let users: [User] }
    struct UserEnvelope: Decodable { let user: User }
    struct UserVolumesEnvelope: Decodable { let volumes: [UserVolume] }
    struct UserVolumeEnvelope: Decodable { let volume: UserVolume }

    struct CreateUserBody: Encodable {
        let email: String
        let username: String?
        let password: String
        let displayName: String?
        let roles: [String]
    }

    struct UpdateUserBody: Encodable {
        let email: String?
        let username: String?
        let displayName: String?
        let roles: [String]?
    }

    struct NewPasswordBody: Encodable {
        let newPassword: String
    }

    struct ChangeOwnPasswordBody: Encodable {
        let currentPassword: String
        let newPassword: String
    }

    struct AddOwnPasswordBody: Encodable {
        let password: String
    }

    struct TwoFactorCodeBody: Encodable {
        let code: String
    }

    /// The body of the two factor routes that ask for the account password.
    struct PasswordBody: Encodable {
        let password: String
    }

    /// `POST /api/auth/totp/confirm` and `POST /api/auth/totp/recovery-codes` answer
    /// `{ "recoveryCodes": [...] }`.
    struct RecoveryCodesEnvelope: Decodable {
        let recoveryCodes: [String]
    }

    /// `GET /api/auth/tokens` answers `{ "tokens": [...] }`.
    struct APITokensEnvelope: Decodable {
        let tokens: [APIToken]
    }

    /// `PATCH /api/auth/tokens/:id` answers `{ "token": {...} }`.
    struct APITokenEnvelope: Decodable {
        let token: APIToken
    }

    /// `password` is left out for an account with no password, and `expiresInDays` for a token that
    /// never expires.
    struct NewAPITokenBody: Encodable {
        let name: String
        let scope: APIToken.Scope
        let expiresInDays: Int?
        let password: String?
    }

    struct NameBody: Encodable {
        let name: String
    }

    /// `GET /api/auth/methods` answers `{ "methods": [...] }`.
    struct SignInMethodsEnvelope: Decodable {
        let methods: [SignInMethod]
    }

    struct AddUserVolumeBody: Encodable {
        let label: String
        let path: String
        let accessMode: String
    }

    struct UpdateUserVolumeBody: Encodable {
        let label: String?
        let accessMode: String
    }
}
