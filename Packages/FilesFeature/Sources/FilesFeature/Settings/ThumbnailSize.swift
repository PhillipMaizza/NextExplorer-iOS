import DesignSystem
import Foundation
import Localization

/// User-facing grid thumbnail size, persisted locally (`AppStorageKeys.thumbnailSize`): a
/// purely client display preference the real server has no concept of, same as
/// `DateDisplayFormat`/`browseViewMode`.
public enum ThumbnailSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .small: L10n.ThumbnailSize.small
        case .medium: L10n.ThumbnailSize.medium
        case .large: L10n.ThumbnailSize.large
        }
    }

    /// Size of the icon or thumbnail within a grid tile. The tile itself keeps one size, so the
    /// setting grows the picture, not the grid.
    public var iconSize: CGFloat {
        switch self {
        case .small: .iconLarge
        case .medium: .size56
        case .large: .size72
        }
    }
}
