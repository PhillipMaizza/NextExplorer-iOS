import SwiftUI

/// Bridges the backend's favorite `icon` string (a Heroicon component name, optionally
/// `"<variant>:Name"`, default `"outline:StarIcon"` — `FAVORITES_DEFAULT_ICON`) to an SF
/// Symbol for display, and back: the picker writes the same bare names the web client uses
/// (`frontend/src/components/FavoriteEditDialog.vue`'s `ICON_NAMES`), so a favorite shows
/// the matching glyph on both platforms.
enum FavoriteIcon {
    /// The pickable names, in the web client's order.
    static let names: [String] = [
        "StarIcon", "FolderIcon", "HomeIcon", "HeartIcon", "DocumentTextIcon", "PhotoIcon",
        "VideoCameraIcon", "MusicalNoteIcon", "CloudIcon", "ArchiveBoxIcon", "BookmarkIcon",
        "GlobeAltIcon", "UserIcon", "UsersIcon", "BuildingOfficeIcon", "BriefcaseIcon",
        "Cog6ToothIcon", "WrenchIcon", "CreditCardIcon", "InboxIcon", "CalendarIcon",
        "EnvelopeIcon", "MapPinIcon", "AcademicCapIcon", "TagIcon", "ShieldCheckIcon",
        "ChartBarIcon", "ClipboardDocumentIcon", "RectangleStackIcon", "CodeBracketIcon",
        "CpuChipIcon", "ServerIcon", "ComputerDesktopIcon", "FolderOpenIcon", "GiftIcon",
        "TruckIcon",
    ]

    static let fallbackName = "StarIcon"

    static func symbol(for token: String?) -> Image {
        Image(systemName: symbolName(for: token))
    }

    static func symbolName(for token: String?) -> String {
        guard let bare = bareName(token), let symbol = symbolByName[bare] else {
            return symbolByName[fallbackName] ?? "star"
        }
        return symbol
    }

    /// Drops an `"outline:"` / `"solid:"` prefix, returning the bare Heroicon name.
    static func bareName(_ token: String?) -> String? {
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else { return nil }
        if let colon = token.firstIndex(of: ":") {
            return String(token[token.index(after: colon)...])
        }
        return token
    }

    /// `true` when the stored token asks for the filled (solid) weight.
    static func isFilled(_ token: String?) -> Bool {
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines),
              let colon = token.firstIndex(of: ":") else { return false }
        return token[..<colon].lowercased() == "solid"
    }

    /// The token to persist for a bare name + weight.
    static func token(name: String, filled: Bool) -> String {
        "\(filled ? "solid" : "outline"):\(name)"
    }

    private static let symbolByName: [String: String] = [
        "StarIcon": "star",
        "FolderIcon": "folder",
        "HomeIcon": "house",
        "HeartIcon": "heart",
        "DocumentTextIcon": "doc.text",
        "PhotoIcon": "photo",
        "VideoCameraIcon": "video",
        "MusicalNoteIcon": "music.note",
        "CloudIcon": "cloud",
        "ArchiveBoxIcon": "archivebox",
        "BookmarkIcon": "bookmark",
        "GlobeAltIcon": "globe",
        "UserIcon": "person",
        "UsersIcon": "person.2",
        "BuildingOfficeIcon": "building.2",
        "BriefcaseIcon": "briefcase",
        "Cog6ToothIcon": "gearshape",
        "WrenchIcon": "wrench",
        "CreditCardIcon": "creditcard",
        "InboxIcon": "tray",
        "CalendarIcon": "calendar",
        "EnvelopeIcon": "envelope",
        "MapPinIcon": "mappin",
        "AcademicCapIcon": "graduationcap",
        "TagIcon": "tag",
        "ShieldCheckIcon": "checkmark.shield",
        "ChartBarIcon": "chart.bar",
        "ClipboardDocumentIcon": "doc.on.clipboard",
        "RectangleStackIcon": "rectangle.stack",
        "CodeBracketIcon": "chevron.left.forwardslash.chevron.right",
        "CpuChipIcon": "cpu",
        "ServerIcon": "server.rack",
        "ComputerDesktopIcon": "desktopcomputer",
        "FolderOpenIcon": "folder.badge.gearshape",
        "GiftIcon": "gift",
        "TruckIcon": "box.truck",
    ]
}
