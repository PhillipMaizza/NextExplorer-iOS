/// The per-user subset of `GET /api/settings`'s `user` object that this client acts on
/// (`backend/src/services/settingsService.js`'s `getUserSettings`). The server also
/// stores sidebar-visibility and share-expiration keys under the same object, but those
/// only apply to the web client's own navigation and to sharing, which this app doesn't
/// have, so they're left undecoded rather than mirrored inertly.
///
/// A brand-new user has no rows in `user_settings` at all, so any key can be absent from
/// the response; decoding falls back to this client's own defaults rather than failing.
public struct UserPreferences: Decodable, Equatable, Sendable {
    public var showHiddenFiles: Bool
    public var showThumbnails: Bool

    public init(showHiddenFiles: Bool = false, showThumbnails: Bool = true) {
        self.showHiddenFiles = showHiddenFiles
        self.showThumbnails = showThumbnails
    }

    private enum CodingKeys: String, CodingKey {
        case showHiddenFiles, showThumbnails
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .showHiddenFiles) ?? false
        showThumbnails = try container.decodeIfPresent(Bool.self, forKey: .showThumbnails) ?? true
    }
}

/// The two `user_settings` keys this client can update via `PATCH /api/settings`.
public enum UserPreferenceKey: String, Sendable {
    case showHiddenFiles
    case showThumbnails
}
