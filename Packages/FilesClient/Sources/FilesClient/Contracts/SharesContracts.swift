import CoreModels
import Foundation

/// Wire types for the Shares endpoints. See `FilesService+Shares.swift`.
extension FilesService {
    struct CreateShareBody: Encodable {
        let sourcePath: String
        let label: String?
        let accessMode: String
        let sharingType: String
        let password: String?
        let userIds: [String]
        let expiresAt: String?
        let permissions: SharePermissions?

        enum CodingKeys: String, CodingKey {
            case sourcePath, label, accessMode, sharingType, password, userIds, expiresAt
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(sourcePath, forKey: .sourcePath)
            try container.encodeIfPresent(label, forKey: .label)
            try container.encode(accessMode, forKey: .accessMode)
            try container.encode(sharingType, forKey: .sharingType)
            try container.encodeIfPresent(password, forKey: .password)
            try container.encode(userIds, forKey: .userIds)
            try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
            try permissions?.encode(to: encoder)
        }
    }

    /// Body for `PUT /api/shares/:id`. `label` / `expiresAt` are always written (`null`
    /// included: that's how the server clears them); `userIds` only when it's a users share;
    /// `password` only when the caller is actually changing or removing it.
    struct UpdateShareBody: Encodable {
        let label: String?
        let accessMode: String
        let sharingType: String
        let expiresAt: String?
        let userIds: [String]?
        let password: UpdateShareRequest.PasswordChange
        let permissions: SharePermissions?

        enum CodingKeys: String, CodingKey {
            case label, accessMode, sharingType, expiresAt, userIds, password
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(label, forKey: .label)
            try container.encode(accessMode, forKey: .accessMode)
            try container.encode(sharingType, forKey: .sharingType)
            try container.encode(expiresAt, forKey: .expiresAt)
            try container.encodeIfPresent(userIds, forKey: .userIds)
            switch password {
            case .keep:
                break
            case .remove:
                try container.encodeNil(forKey: .password)
            case let .set(value):
                try container.encode(value, forKey: .password)
            }
            try permissions?.encode(to: encoder)
        }
    }

    struct ShareLinksEnvelope: Decodable {
        let shares: [Share]
    }

    struct ShareableUsersEnvelope: Decodable {
        let users: [User]
    }
}
