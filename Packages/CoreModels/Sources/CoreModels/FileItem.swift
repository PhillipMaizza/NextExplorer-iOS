import Foundation

/// Mirrors an entry returned by `GET /api/browse/*`, confirmed against
/// `backend/src/services/directoryListingService.js`. `kind` is `"directory"` for
/// folders, otherwise the lowercased file extension (or `"unknown"` with none/an
/// overlong one); there is no separate `isDirectory` field from the server.
public struct FileItem: Codable, Equatable, Identifiable, Sendable {
    public let name: String
    public let path: String
    public let dateModified: Date
    public let size: Int64
    public let kind: String
    public let supportsThumbnail: Bool

    public var isDirectory: Bool { kind == "directory" }
    public var id: String { path.isEmpty ? name : "\(path)/\(name)" }

    /// A cheap content fingerprint (modified date + byte size) used to key on-disk caches of
    /// derived data — the preview/download cache staleness sidecars, and the thumbnail URL
    /// resolution cache. Two loads of an unchanged file produce the same value.
    public var cacheSignature: String {
        "\(dateModified.timeIntervalSince1970)|\(size)"
    }

    // Mirrors `backend/src/config/constants.js` exactly — `GET /api/preview` 415s on
    // anything outside `PREVIEWABLE_EXTENSIONS` (images + rawImages + videos + audios +
    // `["pdf"]`), so guessing at this list wrong means files silently fail to preview.
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "svg", "ico", "tif", "tiff", "avif", "heic"
    ]
    private static let rawImageExtensions: Set<String> = ["nef", "dng", "arw", "cr2", "raf"]
    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "mkv", "webm", "m4v", "avi", "wmv", "flv", "mpg", "mpeg"
    ]
    private static let audioExtensions: Set<String> = [
        "mp3", "wav", "flac", "aac", "m4a", "ogg", "opus", "wma"
    ]
    // Subset of the above `AVFoundation` can actually decode/demux natively — the rest (mkv,
    // avi, wmv, flv, mpg, mpeg, webm; ogg, opus, wma) play through `VLCPlayerView` (libvlc)
    // instead. Both are supported for preview; this flag only picks which player opens.
    private static let nativelyPlayableVideoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    private static let nativelyPlayableAudioExtensions: Set<String> = ["mp3", "wav", "aac", "m4a", "flac"]
    // Mirrors the web client's `archiveExts` (`frontend/src/icons/FileIcon.vue`) — purely a
    // client-side icon grouping, not a server-enforced list like the preview extensions above.
    private static let archiveExtensions: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz"
    ]
    // Extensions the server's own `/api/editor` route (`readTextFileBuffer` in
    // `backend/src/routes/editor.js`) would reject: it 415s videos outright and sniffs
    // everything else for null/control bytes, but checking client-side avoids a round trip
    // just to be told a `.exe` isn't text. Not exhaustive — genuinely unrecognized binary
    // content still gets caught server-side by that same sniff.
    // Rich documents outside the server's `PREVIEWABLE_EXTENSIONS` that QuickLook
    // (`QLPreviewController`) renders natively once the raw bytes are on disk — Word, Excel,
    // PowerPoint, the OpenDocument trio, and RTF. They come down via the unrestricted
    // `POST /api/files/download` (`downloadRawFile`), never `GET /api/preview` (which 415s
    // them). RTF in particular must land here: the text editor would otherwise show its raw
    // `\rtf1\ansi...` markup.
    private static let officeDocumentExtensions: Set<String> = [
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "rtf"
    ]
    private static let knownBinaryExtensions: Set<String> = [
        "exe", "msi", "apk", "dmg", "pkg", "deb", "rpm",
        "ttf", "otf", "woff", "woff2",
        "psd", "ai", "fig", "sketch",
        "db", "sqlite", "sqlite3",
        "bin", "iso", "dll", "dylib", "so", "class", "jar", "a", "o"
    ]
    private var lowercaseKind: String { kind.lowercased() }

    public var isImage: Bool { Self.isImageKind(kind) }
    /// RAW camera formats: `GET /api/preview` always converts these to a JPEG stream
    /// server-side (`rawPreviewService`), regardless of the original extension.
    public var isRawImage: Bool { Self.isRawImageKind(kind) }
    public var isVideo: Bool { Self.isVideoKind(kind) }
    public var isAudio: Bool { Self.isAudioKind(kind) }
    public var isArchive: Bool { Self.isArchiveKind(kind) }
    /// Archive formats this app can actually list the contents of client-side
    /// (`ZIPFoundation`/`Unrar.swift`) — a strict subset of `isArchive`. The other archive
    /// kinds (7z, tar, gz, bz2, xz, tgz) still get the folder-style icon, but tapping them
    /// does nothing: no decoder for those, and the server has no listing-only endpoint either.
    public var isBrowsableArchive: Bool { lowercaseKind == "zip" || lowercaseKind == "rar" }
    /// SVGs are `isImage` (the server's own `PREVIEWABLE_EXTENSIONS` treats them as one) but
    /// unlike raster formats, `UIImage`/`AsyncImage` can't rasterize them — they need
    /// `QLPreviewController`'s WebKit-backed renderer instead, same path as PDFs.
    public var isSVG: Bool { lowercaseKind == "svg" }
    /// Office/rich documents (Word, Excel, PowerPoint, OpenDocument, RTF) — QuickLook renders
    /// these natively, but unlike images/PDF they're outside `PREVIEWABLE_EXTENSIONS`, so they
    /// come down via the generic `POST /api/download` (`FilesClient.downloadRawFile`), not
    /// `GET /api/preview`. Note the real path is `/api/download`, not `/api/files/download` —
    /// the latter looks right by pattern-matching the backend's own `routes/files/download.js`
    /// filename, but that file is mounted at plain `/api` in `routes/index.js`. Got this wrong
    /// once already.
    public var isOfficeDocument: Bool { Self.officeDocumentExtensions.contains(lowercaseKind) }
    /// A PDF. The server refuses to thumbnail these (`backend/src/routes/thumbnails.js`
    /// rejects the `pdf` extension outright), so the client renders the first page itself
    /// from the downloaded file, see `PDFThumbnailImage`.
    public var isPDF: Bool { lowercaseKind == "pdf" }
    /// A web page — offered an "Open in Browser" action that renders it in a `WKWebView`
    /// (the server has no URL an external browser could open; auth is a private cookie).
    public var isHTML: Bool { lowercaseKind == "html" || lowercaseKind == "htm" }
    /// A Google Drive stub file (`.gsheet`, `.gdoc`, …) — tapping it opens the linked Google
    /// document externally rather than showing the JSON stub in the text viewer. See
    /// `GoogleDocsPointer`.
    public var isGoogleDocsPointer: Bool { GoogleDocsPointer.isPointerKind(kind) }

    public static func isImageKind(_ kind: String) -> Bool { imageExtensions.contains(kind.lowercased()) }
    public static func isRawImageKind(_ kind: String) -> Bool { rawImageExtensions.contains(kind.lowercased()) }
    public static func isVideoKind(_ kind: String) -> Bool { videoExtensions.contains(kind.lowercased()) }
    public static func isAudioKind(_ kind: String) -> Bool { audioExtensions.contains(kind.lowercased()) }
    public static func isArchiveKind(_ kind: String) -> Bool { archiveExtensions.contains(kind.lowercased()) }

    /// Worth streaming live (`AVPlayer` + the server's existing HTTP Range support on
    /// `GET /api/preview`) rather than downloading in full first.
    public var isStreamableMedia: Bool { isVideo || isAudio }
    /// Whether `AVPlayer` can actually decode this container/codec combination. `false`
    /// doesn't mean "not media" — it means the UI should show a clear "unsupported format"
    /// message instead of opening a player that will silently fail.
    public var isNativelyPlayable: Bool {
        Self.nativelyPlayableVideoExtensions.contains(lowercaseKind) || Self.nativelyPlayableAudioExtensions.contains(lowercaseKind)
    }
    /// Download-then-`QLPreviewController` kinds: images/RAW/PDF via `GET /api/preview`
    /// (`FilesClient.previewFile`), Word documents via the unrestricted
    /// `POST /api/files/download` (`FilesClient.downloadRawFile`) instead — see
    /// `isOfficeDocument`.
    public var isPreviewableViaDownload: Bool { isImage || isRawImage || lowercaseKind == "pdf" || isOfficeDocument }
    /// Whether tapping this file should attempt any preview/edit UI at all. `false` for
    /// archives and known binary formats — there's nothing useful to show, and for the
    /// text-editor fallback specifically, no point round-tripping to `/api/editor` just to
    /// have the server reject it as binary.
    public var isPreviewable: Bool {
        isStreamableMedia || isPreviewableViaDownload || (!isArchive && !Self.knownBinaryExtensions.contains(lowercaseKind))
    }
    /// The single source of truth for "tapping this should show a toast instead of opening
    /// anything" — shared by the top-level browse list and `ArchiveBrowserView`'s in-archive
    /// rows, so the two don't drift on what counts as unsupported.
    public var isUnsupportedForPreview: Bool {
        // Non native media is no longer unsupported: `VLCPlayerView` handles the containers and
        // codecs AVFoundation can't (`isNativelyPlayable` only chooses which player opens).
        (isArchive && !isBrowsableArchive) || (!isPreviewable && !isBrowsableArchive)
    }

    public init(
        name: String,
        path: String,
        dateModified: Date,
        size: Int64,
        kind: String,
        supportsThumbnail: Bool = false
    ) {
        self.name = name
        self.path = path
        self.dateModified = dateModified
        self.size = size
        self.kind = kind
        self.supportsThumbnail = supportsThumbnail
    }

    private enum CodingKeys: String, CodingKey {
        case name, path, dateModified, size, kind, supportsThumbnail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        dateModified = try container.decode(Date.self, forKey: .dateModified)
        size = try container.decode(Int64.self, forKey: .size)
        kind = try container.decode(String.self, forKey: .kind)
        supportsThumbnail = try container.decodeIfPresent(Bool.self, forKey: .supportsThumbnail) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(dateModified, forKey: .dateModified)
        try container.encode(size, forKey: .size)
        try container.encode(kind, forKey: .kind)
        try container.encode(supportsThumbnail, forKey: .supportsThumbnail)
    }
}
