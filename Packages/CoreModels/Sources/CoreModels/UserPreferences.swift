import Foundation

/// The per-user subset of `GET /api/settings`'s `user` object that this client acts on
/// (`backend/src/services/settingsService.js`'s `getUserSettings`). The server also
/// stores sidebar-visibility keys under the same object, but those only apply to the web
/// client's own navigation, so they're left undecoded rather than mirrored inertly.
///
/// A brand-new user has no rows in `user_settings` at all, so any key can be absent from
/// the response; decoding falls back to this client's own defaults rather than failing.
public struct UserPreferences: Decodable, Equatable, Sendable {
    public var showHiddenFiles: Bool
    public var showThumbnails: Bool
    /// The user's preferred default lifetime for a new share link, or `nil` when they
    /// haven't set one. `backend` stores it as `{ value, unit }` or `null`.
    public var defaultShareExpiration: ShareExpiration?

    public init(
        showHiddenFiles: Bool = false,
        showThumbnails: Bool = true,
        defaultShareExpiration: ShareExpiration? = nil
    ) {
        self.showHiddenFiles = showHiddenFiles
        self.showThumbnails = showThumbnails
        self.defaultShareExpiration = defaultShareExpiration
    }

    /// A relative share-link lifetime: `value` of `unit` from now.
    public struct ShareExpiration: Decodable, Equatable, Sendable {
        public let value: Int
        public let unit: Unit

        public enum Unit: String, Decodable, Sendable {
            case days, weeks, months
        }

        public init(value: Int, unit: Unit) {
            self.value = value
            self.unit = unit
        }

        /// The concrete date this lifetime lands on, measured from `now`. Calendar based so
        /// `months` respects varying month lengths, matching the web client's
        /// `calculateExpirationDate`. Returns `nil` for a non-positive `value`.
        public func expirationDate(from now: Date, calendar: Calendar = .current) -> Date? {
            guard value > 0 else { return nil }
            let component: Calendar.Component
            let amount: Int
            switch unit {
            case .days: component = .day; amount = value
            case .weeks: component = .day; amount = value * 7
            case .months: component = .month; amount = value
            }
            return calendar.date(byAdding: component, value: amount, to: now)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case showHiddenFiles, showThumbnails, defaultShareExpiration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .showHiddenFiles) ?? false
        showThumbnails = try container.decodeIfPresent(Bool.self, forKey: .showThumbnails) ?? true
        defaultShareExpiration = try container.decodeIfPresent(ShareExpiration.self, forKey: .defaultShareExpiration)
    }
}

/// The two `user_settings` keys this client can update via `PATCH /api/settings`.
public enum UserPreferenceKey: String, Sendable {
    case showHiddenFiles
    case showThumbnails
}
