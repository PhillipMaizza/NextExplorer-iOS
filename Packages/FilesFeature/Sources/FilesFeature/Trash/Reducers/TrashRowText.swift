import CoreModels
import Foundation
import Localization

/// The words a trash row shows beside the name, shared by the list, the Mac table and VoiceOver.
enum TrashRowText {
    static let separator = " · "

    /// Where it was deleted from: the personal folder or a volume, and the folder inside it.
    static func location(_ item: TrashItem) -> String {
        guard let location = item.location else { return L10n.Trash.locationUnknown }
        let root = location.isPersonal ? L10n.Trash.locationPersonal : location.name ?? L10n.Trash.locationUnknown
        return location.parent.isEmpty ? root : "\(root)/\(location.parent)"
    }

    static func deletedBy(_ item: TrashItem) -> String {
        if item.deletedBy.isYou {
            return L10n.Trash.deletedByYou
        }
        switch item.deletedBy.label {
        case TrashItem.DeletedBy.shareLinkLabel: return L10n.Trash.deletedByShareLink
        case let .some(label) where !label.isEmpty: return label
        default: return L10n.Trash.deletedByUnknown
        }
    }

    static func deletedOn(_ item: TrashItem) -> String? {
        item.deletedAt?.formatted(date: .abbreviated, time: .omitted)
    }

    static func removal(_ item: TrashItem, now: Date, calendar: Calendar) -> String? {
        guard let days = item.daysUntilRemoval(now: now, calendar: calendar) else { return nil }
        return days == 0 ? L10n.Trash.removedToday : L10n.Trash.removedIn(days)
    }

    /// The row's second line: location, who deleted it, when it goes, and its badges.
    static func subtitle(_ item: TrashItem, now: Date, calendar: Calendar) -> String {
        var parts = [location(item), L10n.Trash.deletedBy(deletedBy(item))]
        if let removal = removal(item, now: now, calendar: calendar) {
            parts.append(removal)
        }
        if item.shareCount > 0 {
            parts.append(L10n.Trash.sharesBadge)
        }
        if !item.isAvailable {
            parts.append(L10n.Trash.unavailable)
        }
        return parts.joined(separator: separator)
    }

    /// The extension a row's file icon is chosen by.
    static func kind(_ name: String, isDirectory: Bool) -> String {
        isDirectory ? FileItem.directoryKind : (name as NSString).pathExtension.lowercased()
    }
}
