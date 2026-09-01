import CoreModels
import Foundation

/// Wire types for the Settings/branding endpoints. See `FilesService+Settings.swift`.
extension FilesService {
    /// `GET /api/settings` / the `PATCH` echo. Only `user` and `branding` are decoded;
    /// the admin-only `thumbnails`/`access` objects aren't modeled by this envelope.
    struct SettingsEnvelope: Decodable {
        let user: UserPreferences?
        let branding: Branding?
    }

    struct PatchPreferencesBody: Encodable {
        let user: [String: Bool]
    }

    struct PatchBrandingBody: Encodable {
        struct Branding: Encodable {
            let appName: String
            let appLogoUrl: String
        }
        let branding: Branding
    }

    struct PatchThumbnailsBody: Encodable {
        struct Thumbnails: Encodable {
            let enabled: Bool
            let size: Int
            let quality: Int
            let concurrency: Int
        }
        let thumbnails: Thumbnails
    }

    struct PatchAccessBody: Encodable {
        struct Access: Encodable {
            let rules: [AccessRule]
        }
        let access: Access
    }

    struct LogoUploadEnvelope: Decodable {
        let logoUrl: String
    }
}
