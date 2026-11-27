import CoreModels
import DesignSystem
import Foundation
import Localization

/// The words a trash row shows beside the name, shared by the list, the Mac table and VoiceOver.
enum TrashRowText {
    static let separator = " · "
    private static let secondsPerDay: Double = 86400

    /// Where it was deleted from: the personal folder or a volume, and the folder inside it.
    static func location(_ item: TrashItem) -> String {
        guard let location = item.location else { return L10n.Trash.locationUnknown }
        let root = if location.isPersonal {
            isOwnPersonalFolder(item) ? L10n.Browse.myFiles : L10n.Trash.locationPersonal
        } else {
            location.name ?? L10n.Trash.locationUnknown
        }
        return location.parent.isEmpty ? root : "\(root)/\(location.parent)"
    }

    private static func isOwnPersonalFolder(_ item: TrashItem) -> Bool {
        guard let openPath = item.openPath else { return false }
        return openPath == PersonalSpace.rootPath || openPath.hasPrefix(PersonalSpace.rootPath + "/")
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

    /// How long until it goes, as a plain count ("30 days") in the app's language.
    static func timeLeft(_ item: TrashItem, now: Date, calendar: Calendar) -> String? {
        guard let days = item.daysUntilRemoval(now: now, calendar: calendar) else { return nil }
        guard days > 0 else { return L10n.Trash.removedToday }
        return Duration.seconds(Double(days) * secondsPerDay)
            .formatted(.units(allowed: [.days], width: .wide).locale(LocalizationOverride.locale))
    }

    /// The row's details under the name: whether it can be reached, how long it has left, who deleted
    /// it and whether it had share links, then on their own line the folder it came from.
    static func subtitle(_ item: TrashItem, now: Date, calendar: Calendar) -> String {
        var parts: [String] = []
        if !item.isAvailable {
            parts.append(L10n.Trash.unavailable)
        }
        if let timeLeft = timeLeft(item, now: now, calendar: calendar) {
            parts.append(timeLeft)
        }
        parts.append(L10n.Trash.deletedBy(deletedBy(item)))
        if item.shareCount > 0 {
            parts.append(L10n.Trash.sharesBadge)
        }
        return parts.joined(separator: separator) + "\n" + location(item)
    }

    /// The extension a row's file icon is chosen by.
    static func kind(_ name: String, isDirectory: Bool) -> String {
        isDirectory ? FileItem.directoryKind : (name as NSString).pathExtension.lowercased()
    }
}
