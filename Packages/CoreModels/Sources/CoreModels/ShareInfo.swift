import Foundation

/// Public metadata for a share link, from `GET /api/share/<token>/info` (confirmed against
/// `backend/src/routes/shares.js`). Unauthenticated — this is what a recipient sees before
/// deciding to open the link. The full contents come from browsing the logical path
/// `share/<token>` once opened.
public struct ShareInfo: Decodable, Equatable, Sendable {
    public let shareToken: String
    public let label: String?
    public let isDirectory: Bool
    public let hasPassword: Bool
    public let sharingType: ShareTarget
    public let expiresAt: Date?
    public let isExpired: Bool

    public init(
        shareToken: String,
        label: String? = nil,
        isDirectory: Bool,
        hasPassword: Bool = false,
        sharingType: ShareTarget = .anyone,
        expiresAt: Date? = nil,
        isExpired: Bool = false
    ) {
        self.shareToken = shareToken
        self.label = label
        self.isDirectory = isDirectory
        self.hasPassword = hasPassword
        self.sharingType = sharingType
        self.expiresAt = expiresAt
        self.isExpired = isExpired
    }

    /// Restricted to named recipients — a signed-in user who isn't one gets a 403 on
    /// browse, so the sheet warns before opening.
    public var isRestrictedToUsers: Bool {
        sharingType == .users
    }
}
