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
