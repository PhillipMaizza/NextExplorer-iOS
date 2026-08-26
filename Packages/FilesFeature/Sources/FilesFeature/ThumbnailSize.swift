import DesignSystem
import Foundation

/// User-facing grid thumbnail size, persisted locally (`@AppStorage("thumbnailSize")`) — a
/// purely client display preference the real server has no concept of, same as
/// `DateDisplayFormat`/`browseViewMode`.
public enum ThumbnailSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// Minimum width of a grid column — drives how many tiles fit per row.
    public var gridItemMinWidth: CGFloat {
        switch self {
        case .small: 76
        case .medium: 100
        case .large: 140
        }
    }

    /// Size of the icon/thumbnail image within a grid tile.
    public var iconSize: CGFloat {
        switch self {
        case .small: .iconLarge
        case .medium: .size56
        case .large: .size72
        }
    }
}
