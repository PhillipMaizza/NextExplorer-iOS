import CoreModels
import Foundation
import Localization

/// The snippet shown as a search hit's subtitle: the matched line with its own indentation
/// trimmed off (code lines are indented, which would otherwise push the text far right under a
/// big blank gap). `nil` for a filename only hit or an all whitespace line.
func searchResultSnippet(_ result: SearchResultItem) -> String? {
    guard let line = result.matchLine?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else { return nil }
    return line
}

/// The small "Line N" label shown under a content match's snippet. `nil` when the hit is a
/// filename match or the server reported no line number.
func searchResultLineLabel(_ result: SearchResultItem) -> String? {
    guard result.matchLine != nil, let lineNumber = result.matchLineNumber else { return nil }
    return L10n.Browse.searchMatchLineLabel(lineNumber)
}

/// The match a result's row says, as the web client labels it, with the matched line when there is
/// one: "Contents, Line 12". `nil` for a local match that carries no match.
func searchResultMatchDescription(_ result: SearchResultItem) -> String? {
    let parts = [result.matchKind?.title, searchResultLineLabel(result)].compactMap(\.self)
    return parts.isEmpty ? nil : parts.joined(separator: ", ")
}

/// The label under a list row's snippet: the match when the hit is not just its name, where the
/// name itself already says why it is there.
func searchResultRowLabel(_ result: SearchResultItem) -> String? {
    result.matchKind == .name ? nil : searchResultMatchDescription(result)
}

private enum ThumbnailPlaceholder {
    static let date = Date(timeIntervalSince1970: 0)
    static let size: Int64 = 0
}

extension SearchResultItem {
    /// Search results only report `dir`/`file` for kind, so a file's comes from its name: what
    /// the row icon shows and the preview opens it as.
    var displayKind: String {
        isDirectory ? kind : (name as NSString).pathExtension.lowercased()
    }

    /// The `FileItem` a tapped file hit opens in the preview, like a tapped row: its kind from its
    /// name, `unknown` without an extension. Size and modified date are unknown, so the preview
    /// cache treats it as fresh and fetches it.
    func previewItem(openedAt date: Date) -> FileItem {
        let kind = displayKind
        return FileItem(name: name, path: path, dateModified: date, size: 0, kind: kind.isEmpty ? "unknown" : kind, supportsThumbnail: false)
    }

    /// A thumbnail capable `FileItem` for a file hit; `nil` for a folder, which keeps its glyph.
    /// Hits carry no size or modified date, so stable placeholders hold the thumbnail cache key
    /// steady across renders. `supportsThumbnail` is set for the kinds the server thumbnails
    /// (images, RAW, video); a PDF renders its first page on device off its kind alone.
    var thumbnailFile: FileItem? {
        guard !isDirectory else { return nil }
        let kind = displayKind
        return FileItem(
            name: name,
            path: path,
            dateModified: ThumbnailPlaceholder.date,
            size: ThumbnailPlaceholder.size,
            kind: kind,
            supportsThumbnail: FileItem.isImageKind(kind) || FileItem.isRawImageKind(kind) || FileItem.isVideoKind(kind)
        )
    }
}
