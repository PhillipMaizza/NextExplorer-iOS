import Foundation

/// A coarse file type bucket derived from the `kind` the backend sends (a lowercased extension,
/// or `"directory"`). The backend has no category field of its own, so this is the client side
/// grouping used by the search type filter. `allCases` is ordered for display.
public enum FileCategory: String, CaseIterable, Sendable, Hashable {
    case folder
    case image
    case video
    case audio
    case document
    case archive
    case other

    /// Buckets a `kind` (and the directory flag, since a folder's kind is `"directory"`). Anything
    /// not recognised as one of the media/document groups falls through to `.other`.
    public static func of(kind: String, isDirectory: Bool) -> FileCategory {
        if isDirectory {
            return .folder
        }
        let lowered = kind.lowercased()
        if FileItem.isImageKind(lowered) || FileItem.isRawImageKind(lowered) {
            return .image
        }
        if FileItem.isVideoKind(lowered) {
            return .video
        }
        if FileItem.isAudioKind(lowered) {
            return .audio
        }
        if FileItem.isArchiveKind(lowered) {
            return .archive
        }
        if documentExtensions.contains(lowered) {
            return .document
        }
        return .other
    }

    /// PDFs, office files, and the plain text / data / code formats the app can open in its text
    /// editor. Mirrors the kinds `CodeEditorLanguage` and the office/preview paths already handle,
    /// so "Document" lines up with what actually opens as a readable document.
    private static let documentExtensions: Set<String> = [
        "pdf",
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "pages", "numbers", "key", "rtf",
        "txt", "md", "markdown", "log", "csv", "tsv",
        "json", "xml", "yml", "yaml", "toml", "ini", "plist",
        "html", "htm", "css", "scss",
        "js", "jsx", "ts", "tsx", "py", "rb", "php", "go", "rs", "java",
        "c", "cpp", "cc", "cxx", "h", "hpp", "cs", "sql", "sh", "bash", "zsh", "swift",
    ]
}
