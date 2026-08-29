import Foundation

/// Server branding: the app name and logo an admin sets under Settings. Confirmed against
/// `backend/src/services/settingsService.js`'s `sanitizeBranding` — `GET /api/branding`
/// returns this unauthenticated, `PATCH /api/settings` (admin) updates it.
///
/// The server also stores `showPoweredBy`; this app has no footer for it, so it's neither
/// decoded nor sent. `PATCH` merges server side, so omitting a key leaves it untouched.
public struct Branding: Codable, Equatable, Sendable {
    public var appName: String
    public var appLogoUrl: String

    /// The server's own defaults when nothing has been set (`sanitizeBranding`).
    public static let defaultAppName = "Explorer"
    public static let defaultLogoPath = "/logo.svg"

    /// `@Shared(.inMemory(...))` key: the branding `SettingsFeature` fetches and
    /// `ServerDetailsFeature` writes back after a successful save.
    public static let sharedKey = "serverBranding"

    public init(appName: String = Branding.defaultAppName, appLogoUrl: String = Branding.defaultLogoPath) {
        self.appName = appName
        self.appLogoUrl = appLogoUrl
    }

    private enum CodingKeys: String, CodingKey {
        case appName, appLogoUrl
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appName = try container.decodeIfPresent(String.self, forKey: .appName) ?? Branding.defaultAppName
        appLogoUrl = try container.decodeIfPresent(String.self, forKey: .appLogoUrl) ?? Branding.defaultLogoPath
    }

    /// `true` once an admin has uploaded a logo, i.e. it's no longer the packaged default.
    public var hasCustomLogo: Bool {
        !appLogoUrl.isEmpty && appLogoUrl != Branding.defaultLogoPath
    }

    /// The logo as an absolute URL. `appLogoUrl` is usually server relative
    /// (`/static/logos/custom-logo.png`); an already-absolute value is returned as is.
    public func resolvedLogoURL(serverURL: URL) -> URL? {
        guard hasCustomLogo else { return nil }
        if let absolute = URL(string: appLogoUrl), absolute.scheme != nil { return absolute }
        return URL(string: appLogoUrl, relativeTo: serverURL)?.absoluteURL
    }
}
