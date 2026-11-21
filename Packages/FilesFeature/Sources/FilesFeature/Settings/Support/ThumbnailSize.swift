import Foundation
import Localization

/// User facing grid size, persisted locally (`AppStorageKeys.thumbnailSize`, named for its first
/// meaning): how many files share a row. A purely client display preference the real server has no
/// concept of, same as `DateDisplayFormat`/`browseViewMode`.
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

    /// Files per row on a compact width screen (an iPhone): the grid size the user picks.
    public var columnCount: Int {
        switch self {
        case .small: 4
        case .medium: 3
        case .large: 2
        }
    }

    /// A file column's narrowest width on a regular width screen (an iPad, an open Duo), where a
    /// fixed count would make each tile huge: columns are added as the width allows instead.
    public var minimumColumnWidth: CGFloat {
        switch self {
        case .small: 96
        case .medium: 128
        case .large: 192
        }
    }

    /// Folder cards per row on a compact width screen: one fewer than files, never under two, as a card
    /// carries its name beside more room than a tile.
    public var folderColumnCount: Int {
        max(columnCount - 1, 2)
    }

    public var minimumFolderColumnWidth: CGFloat {
        switch self {
        case .small: 160
        case .medium: 200
        case .large: 260
        }
    }

    /// The roomiest size: wider pictures and bigger names, as two to a row allows.
    public var isRoomy: Bool {
        self == .large
    }

    /// The densest size: folder cards shrink to fit three to a row.
    public var isDense: Bool {
        self == .small
    }
}
