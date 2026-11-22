import CoreModels
import Localization

enum VersionedFileWords {
    static func zone(_ zone: VersionedZone?) -> String {
        guard let zone else { return L10n.VersionedFiles.zoneUnknown }
        switch zone.kind {
        case .personal: return L10n.VersionedFiles.zoneKindPersonal(zone.name)
        case .userVolume: return L10n.VersionedFiles.zoneKindUserVolume(zone.name)
        case .volume: return zone.name
        }
    }

    static func state(_ state: VersionedFileState?) -> String {
        switch state {
        case .none: L10n.VersionedFiles.anyState
        case .live: L10n.VersionedFiles.stateLive
        case .trashed: L10n.VersionedFiles.stateTrashed
        case .orphaned: L10n.VersionedFiles.stateOrphaned
        }
    }

    static func sort(_ sort: VersionedFileSort) -> String {
        switch sort {
        case .bytes: L10n.VersionedFiles.sortBytes
        case .versions: L10n.VersionedFiles.sortVersions
        case .newest: L10n.VersionedFiles.sortNewest
        case .path: L10n.VersionedFiles.sortPath
        }
    }

    static func subtitle(_ version: FileVersion) -> String? {
        var parts: [String] = []
        if let label = version.label, !label.isEmpty {
            parts.append(label)
        }
        if version.isPinned {
            parts.append(L10n.VersionedFiles.versionPinned)
        }
        if version.isAvailable == false {
            parts.append(L10n.VersionedFiles.versionUnavailable)
        }
        if let author = version.author?.label, !author.isEmpty {
            parts.append(L10n.VersionedFiles.versionBy(author))
        }
        return parts.isEmpty ? nil : ServerSettingsMetrics.joined(parts)
    }
}
