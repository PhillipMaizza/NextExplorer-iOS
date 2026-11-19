import CoreModels
import DesignSystem
import Foundation
import Localization

/// A share's facts worded once for the iOS share page and the Mac inspector.
@MainActor
struct SharedShareFacts {
    let share: Share
    let notice: SharedFeature.ExpiryNotice?
    let dateFormat: DateDisplayFormat

    var isExpired: Bool {
        notice == .expired
    }

    var password: String {
        share.hasPassword ? L10n.Common.on : L10n.Common.off
    }

    var expiresTitle: String {
        isExpired ? L10n.Shared.metaExpired : L10n.Shared.metaExpires
    }

    /// The date, with the day countdown beside it inside the warning window.
    var expires: String {
        guard let expiresAt = share.expiresAt else { return L10n.Common.never }
        let date = dateFormat.string(from: expiresAt)
        if case let .daysLeft(days) = notice {
            return L10n.Shared.statusStep(date, L10n.Shared.daysLeft(days))
        }
        return date
    }

    var expiresStyle: Typography.TextStyle {
        Self.style(for: notice)
    }

    var label: String {
        share.trimmedLabel ?? L10n.Common.none
    }

    var created: String {
        dateFormat.string(from: share.createdAt)
    }

    var lastOpened: String {
        Self.lastOpened(share.lastAccessedAt)
    }

    var downloads: String {
        share.downloadCount.formatted()
    }

    var linkModeTitle: String {
        share.isDirectory ? L10n.Shared.folderLinkOpensAs : L10n.Shared.fileLinkOpensAs
    }

    /// Under the facts of an expired share: when it stopped and how to bring it back.
    var expiredNote: String? {
        guard isExpired, let expiresAt = share.expiresAt else { return nil }
        return L10n.Shared.expiredFooter(dateFormat.string(from: expiresAt))
    }

    /// Red once expired, the warning colour inside the countdown window.
    static func style(for notice: SharedFeature.ExpiryNotice?) -> Typography.TextStyle {
        switch notice {
        case .expired: .error
        case .daysLeft: .warning
        case nil: .secondary
        }
    }

    static func lastOpened(_ date: Date?) -> String {
        date.map(OfflineRelativeTime.string(from:)) ?? L10n.Common.never
    }
}
