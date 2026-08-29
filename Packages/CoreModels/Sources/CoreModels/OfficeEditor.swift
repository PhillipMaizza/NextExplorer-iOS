import Foundation

/// Which web-based office editor should open a given document. The backend exposes two
/// (`backend/src/routes/onlyoffice.js`, `backend/src/routes/collabora.js`); this app picks
/// one per file the same way the web frontend does
/// (`frontend/src/plugins/{onlyoffice,collabora}/*.js`).
public enum OfficeEditor: String, Equatable, Sendable, CaseIterable {
    case onlyOffice
    case collabora

    /// `UserDefaults` key for the client-local "which editor to prefer when both are
    /// enabled" setting. The web client persists the same choice in local storage.
    public static let preferenceStorageKey = "officeEditorPreference"
    /// The default preference, matching the web client's default of ONLYOFFICE.
    public static let defaultPreference: OfficeEditor = .onlyOffice

    /// Resolve a stored raw preference string, falling back to the default for anything
    /// unrecognised.
    public static func preference(fromRawValue raw: String) -> OfficeEditor {
        OfficeEditor(rawValue: raw) ?? defaultPreference
    }
}

/// `edit` opens a writable session; `view` a read-only one. Sent as the `mode` field to the
/// `/config` endpoints, which also force `view` for read-only shares regardless.
public enum OfficeEditorMode: String, Equatable, Sendable {
    case edit
    case view
}

public enum OfficeEditorSupport {
    /// The web frontend's fallback lists, used when `GET /api/features` reports an empty
    /// `extensions` array (the env default). ONLYOFFICE's list omits `txt`; Collabora's
    /// includes it.
    public static let onlyOfficeDefaultExtensions: Set<String> = [
        "docx", "doc", "odt", "rtf", "xlsx", "xls", "ods", "csv", "pptx", "ppt", "odp",
    ]
    public static let collaboraDefaultExtensions: Set<String> = [
        "docx", "doc", "odt", "rtf", "txt", "xlsx", "xls", "ods", "csv", "pptx", "ppt", "odp",
    ]

    /// The editor that should open `fileExtension`, or `nil` if neither applies. When both
    /// editors support the extension `preference` breaks the tie (default ONLYOFFICE, matching
    /// the web default); when only one is enabled it is used only if the extension is in its
    /// advertised list, falling back to the frontend default set when that list is empty.
    public static func editor(
        for fileExtension: String,
        features: ServerFeatures.OfficeEditors,
        preference: OfficeEditor = .onlyOffice
    ) -> OfficeEditor? {
        let ext = fileExtension.lowercased()

        let onlyOfficeMatches = features.isOnlyOfficeEnabled
            && matches(ext, advertised: features.onlyOfficeExtensions, fallback: onlyOfficeDefaultExtensions)
        let collaboraMatches = features.isCollaboraEnabled
            && matches(ext, advertised: features.collaboraExtensions, fallback: collaboraDefaultExtensions)

        if onlyOfficeMatches && collaboraMatches { return preference }
        if onlyOfficeMatches { return .onlyOffice }
        if collaboraMatches { return .collabora }
        return nil
    }

    private static func matches(_ ext: String, advertised: [String], fallback: Set<String>) -> Bool {
        let list = advertised.isEmpty
            ? fallback
            : Set(advertised.map { $0.lowercased() })
        return list.contains(ext)
    }
}
