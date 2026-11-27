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

enum DirectLinkChoice: Hashable, Identifiable {
    case openInBrowser
    case download
    case raw
    case zip

    var id: Self {
        self
    }

    var mode: DirectLinkMode {
        switch self {
        case .openInBrowser, .zip: .auto
        case .download: .download
        case .raw: .raw
        }
    }

    var title: String {
        switch self {
        case .openInBrowser: L10n.Shared.directOpen
        case .download: L10n.Common.download
        case .raw: L10n.DirectLinkMode.raw
        case .zip: L10n.Shared.directZip
        }
    }

    var detail: String {
        switch self {
        case .openInBrowser: L10n.Shared.directOpenDetail
        case .download: L10n.Shared.directDownloadDetail
        case .raw: L10n.Shared.directRawDetail
        case .zip: L10n.Shared.directZipDetail
        }
    }
}

extension Share {
    var directLinkChoices: [DirectLinkChoice] {
        guard isDownloadAllowed else { return [] }
        return isDirectory ? [.zip] : [.openInBrowser, .download, .raw]
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

    var itemName: String {
        if let leaf = trimmedSourcePath?.split(separator: "/").last {
            return String(leaf)
        }
        if let sourceName, !sourceName.isEmpty {
            return sourceName
        }
        return displayName
    }

    var itemLocation: String {
        (trimmedSourcePath?.split(separator: "/").dropLast() ?? []).joined(separator: "/")
    }

    var browsePath: String? {
        guard let path = trimmedSourcePath, !path.isEmpty else { return nil }
        return sourceSpace == PersonalSpace.rootPath ? "\(PersonalSpace.rootPath)/\(path)" : path
    }

    func fileItem(size: Int64 = 0, modified: Date? = nil) -> FileItem? {
        isDirectory ? nil : item(size: size, modified: modified)
    }

    func item(size: Int64 = 0, modified: Date? = nil) -> FileItem? {
        guard let path = browsePath else { return nil }
        return fileItem(
            named: (path as NSString).lastPathComponent,
            in: (path as NSString).deletingLastPathComponent,
            size: size,
            modified: modified
        )
    }

    var receivedPath: String {
        "\(ReceivedShareSpace.rootPath)/\(shareToken)"
    }

    var receivedFileItem: FileItem? {
        guard !isDirectory, let sourceName, !sourceName.isEmpty else { return nil }
        return fileItem(named: sourceName, in: receivedPath, size: 0, modified: nil)
    }

    private func fileItem(named name: String, in parent: String, size: Int64, modified: Date?) -> FileItem {
        let kind = isDirectory ? FileItem.directoryKind : (name as NSString).pathExtension.lowercased()
        return FileItem(
            name: name,
            path: parent,
            dateModified: modified ?? updatedAt,
            size: size,
            kind: kind,
            supportsThumbnail: FileItem.isImageKind(kind) || FileItem.isVideoKind(kind) || FileItem.isAudioKind(kind)
        )
    }

    private static func origin(of serverURL: URL) -> String {
        if let scheme = serverURL.scheme, let host = serverURL.host {
            let port = serverURL.port.map { ":\($0)" } ?? ""
            return "\(scheme)://\(host)\(port)"
        }
        return serverURL.absoluteString
    }
}

enum ReceivedShareSpace {
    static let rootPath = PersonalSpace.receivedSharesRootPath

    static func shareRoot(of path: String) -> String? {
        PersonalSpace.receivedShareRoot(of: path)
    }
}
