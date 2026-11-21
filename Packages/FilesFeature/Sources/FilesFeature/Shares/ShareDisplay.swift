import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// Presentation titles for the share enums. Kept out of `CoreModels` so the model layer
/// stays free of user facing copy.
extension ShareAccessMode {
    var title: String {
        switch self {
        case .readonly: L10n.AccessMode.readonly
        case .readwrite: L10n.AccessMode.readwrite
        }
    }
}

extension ShareTarget {
    var title: String {
        switch self {
        case .anyone: L10n.ShareTarget.anyone
        case .users: L10n.ShareTarget.users
        }
    }
}

extension DirectLinkMode {
    var title: String {
        switch self {
        case .auto: L10n.DirectLinkMode.auto
        case .inline: L10n.DirectLinkMode.inline
        case .raw: L10n.DirectLinkMode.raw
        case .download: L10n.DirectLinkMode.download
        }
    }
}

/// The two links a share hands out, as the web builds them: the share page and the direct
/// file (or folder zip) endpoint.
extension Share {
    func shareLink(serverURL: URL) -> String {
        "\(Self.origin(of: serverURL))/share/\(shareToken)"
    }

    func directLink(serverURL: URL, mode: DirectLinkMode) -> String {
        let base = "\(Self.origin(of: serverURL))/api/share/\(shareToken)/file"
        return mode == .auto ? base : "\(base)?mode=\(mode.rawValue)"
    }

    /// Copies the share link and returns the toast that confirms it.
    @MainActor
    func copyShareLink(serverURL: URL) -> String {
        PlatformPasteboard.copy(shareLink(serverURL: serverURL))
        return L10n.Shared.copiedShareLink
    }

    /// Copies the direct file or folder ZIP link and returns the toast that confirms it.
    @MainActor
    func copyDirectLink(serverURL: URL, mode: DirectLinkMode) -> String {
        PlatformPasteboard.copy(directLink(serverURL: serverURL, mode: mode))
        return isDirectory ? L10n.Shared.copiedFolderZip : L10n.Shared.copiedDirectFile
    }

    /// Who it reaches, as a title: anyone with the link, or how many people.
    var audienceTitle: String {
        sharingType == .anyone ? L10n.Shared.anyoneWithLink : L10n.Shared.peopleCount(permittedUserIds?.count ?? 0)
    }

    /// Who it reaches, as a glyph: a globe for a public link, people otherwise.
    var audienceIcon: Image {
        sharingType.icon
    }

    /// The label as shown: trimmed, nil when blank.
    var trimmedLabel: String? {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else { return nil }
        return label
    }

    /// The shared path without its leading or trailing slashes.
    var trimmedSourcePath: String? {
        sourcePath?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func origin(of serverURL: URL) -> String {
        if let scheme = serverURL.scheme, let host = serverURL.host {
            let port = serverURL.port.map { ":\($0)" } ?? ""
            return "\(scheme)://\(host)\(port)"
        }
        return serverURL.absoluteString
    }
}
