import Foundation

/// Which files the text editor opens, as the web client decides it
/// (`frontend/src/config/editor.js`): its default list plus whatever the server adds through
/// `EDITOR_EXTENSIONS` (`GET /api/features` → `editor.extensions`). Creating a new file is limited
/// to these, since an empty `.jpg` or `.docx` is not something anyone can open and fill in.
public enum EditableTextFiles {
    public static let defaultExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "json", "json5", "yml", "yaml", "xml", "log", "ini",
        "cfg", "conf", "env", "properties", "js", "jsx", "mjs", "cjs", "ts", "tsx", "py", "rb", "php",
        "java", "c", "h", "cpp", "hpp", "cs", "go", "rs", "swift", "kt", "scala", "sh", "bash", "zsh",
        "ps1", "bat", "vue", "svelte", "astro", "html", "css", "scss", "sass", "less",
    ]

    /// The text after the last dot, lowercased: `notes.TXT` is `txt`, `.env` is `env`. `nil` for a
    /// name without one or ending in a dot.
    public static func fileExtension(of name: String) -> String? {
        guard let dot = name.lastIndex(of: ".") else { return nil }
        let ext = name[name.index(after: dot)...].lowercased()
        return ext.isEmpty ? nil : ext
    }

    public static func isEditable(name: String, serverExtensions: [String] = []) -> Bool {
        guard let ext = fileExtension(of: name) else { return false }
        return defaultExtensions.contains(ext) || serverExtensions.contains(ext)
    }
}
