import CoreModels

/// Which viewer shows a file. One order for every place that decides it (the reducer's fetch on
/// open, the preview router, the cover's ready check and the gallery's pages), so they never
/// disagree about a file.
enum PreviewKind: Equatable {
    /// A file the app has no viewer for: its icon, name and size.
    case unsupported
    /// Video or audio, streamed.
    case media
    /// A zip or rar the archive browser lists.
    case archive
    /// A photo or RAW image, decoded in the gallery.
    case image
    /// A PDF, office document or other file Quick Look shows once downloaded.
    case document
    /// Plain text or code from the editor endpoint.
    case text

    init(_ item: FileItem) {
        if item.isUnsupportedForPreview {
            self = .unsupported
        } else if item.isStreamableMedia {
            self = .media
        } else if item.isBrowsableArchive {
            self = .archive
        } else if item.isImage || item.isRawImage, !item.isSVG {
            self = .image
        } else if item.isPreviewableViaDownload {
            self = .document
        } else {
            self = .text
        }
    }
}
