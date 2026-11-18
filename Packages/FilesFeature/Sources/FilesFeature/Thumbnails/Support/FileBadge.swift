import CoreModels
import DesignSystem
import SwiftUI

/// A colored text badge for an extension the web app dedicates a distinct color to: kept as raw
/// hex to match it exactly rather than deriving DS semantic colors for about 50 one off brand colors.
struct FileBadge {
    let label: String
    let background: Color
    let foreground: Color
}

extension FileItem {
    /// Mirrors the web client's per extension badge table exactly: same labels, same hex colors,
    /// so a `.py` file looks the same shade of blue here as it does on the web.
    static func badge(forKind kind: String) -> FileBadge? {
        switch kind.lowercased() {
        case "pdf": FileBadge(label: "PDF", background: Color(hex: 0xE81123), foreground: .white)
        case "doc", "docx", "rtf": FileBadge(label: "DOC", background: Color(hex: 0x2563EB), foreground: .white)
        case "xls", "xlsx": FileBadge(label: "XLS", background: Color(hex: 0x16A34A), foreground: .white)
        case "ppt", "pptx": FileBadge(label: "PPT", background: Color(hex: 0xF97316), foreground: .white)
        case "csv": FileBadge(label: "CSV", background: Color(hex: 0x22C55E), foreground: .white)
        case "txt": FileBadge(label: "TXT", background: Color(hex: 0x6B7280), foreground: .white)
        case "md", "markdown": FileBadge(label: "MD", background: Color(hex: 0x0EA5E9), foreground: .white)
        case "html", "htm": FileBadge(label: "HTML", background: Color(hex: 0xE44D26), foreground: .white)
        case "gsheet": FileBadge(label: "SHEET", background: Color(hex: 0x188038), foreground: .white)
        case "gdoc": FileBadge(label: "DOC", background: Color(hex: 0x1A73E8), foreground: .white)
        case "gslides": FileBadge(label: "SLIDES", background: Color(hex: 0xF9AB00), foreground: Color(hex: 0x111827))
        case "gform": FileBadge(label: "FORM", background: Color(hex: 0x7627BB), foreground: .white)
        case "gdraw": FileBadge(label: "DRAW", background: Color(hex: 0xEA4335), foreground: .white)
        case "css": FileBadge(label: "CSS", background: Color(hex: 0x2965F1), foreground: .white)
        case "scss": FileBadge(label: "SCSS", background: Color(hex: 0xC6538C), foreground: .white)
        case "less": FileBadge(label: "LESS", background: Color(hex: 0x1D365D), foreground: .white)
        case "js": FileBadge(label: "JS", background: Color(hex: 0xF7DF1E), foreground: .black)
        case "ts": FileBadge(label: "TS", background: Color(hex: 0x3178C6), foreground: .white)
        case "jsx": FileBadge(label: "JSX", background: Color(hex: 0x61DAFB), foreground: .black)
        case "tsx": FileBadge(label: "TSX", background: Color(hex: 0x3178C6), foreground: .white)
        case "vue": FileBadge(label: "VUE", background: Color(hex: 0x41B883), foreground: Color(hex: 0x0B1921))
        case "json": FileBadge(label: "JSON", background: Color(hex: 0x8B5CF6), foreground: .white)
        case "yml", "yaml": FileBadge(label: "YAML", background: Color(hex: 0x14B8A6), foreground: Color(hex: 0x073B3A))
        case "xml": FileBadge(label: "XML", background: Color(hex: 0xEC4899), foreground: .white)
        case "sh", "bash", "zsh": FileBadge(label: "SH", background: Color(hex: 0x374151), foreground: .white)
        case "py": FileBadge(label: "PY", background: Color(hex: 0x3776AB), foreground: .white)
        case "rb": FileBadge(label: "RB", background: Color(hex: 0xCC342D), foreground: .white)
        case "php": FileBadge(label: "PHP", background: Color(hex: 0x777BB4), foreground: .white)
        case "go": FileBadge(label: "GO", background: Color(hex: 0x00ADD8), foreground: Color(hex: 0x073B4C))
        case "rs": FileBadge(label: "RS", background: Color(hex: 0xDEA584), foreground: .black)
        case "java": FileBadge(label: "JAVA", background: Color(hex: 0xE11D48), foreground: .white)
        case "kt", "kts": FileBadge(label: "KT", background: Color(hex: 0x7F52FF), foreground: .white)
        case "swift": FileBadge(label: "SWIFT", background: Color(hex: 0xFA7343), foreground: .white)
        case "c": FileBadge(label: "C", background: Color(hex: 0x5C6BC0), foreground: .white)
        case "cpp", "cc", "cxx": FileBadge(label: "CPP", background: Color(hex: 0x00599C), foreground: .white)
        case "cs": FileBadge(label: "CS", background: Color(hex: 0x239120), foreground: .white)
        case "sql": FileBadge(label: "SQL", background: Color(hex: 0x0EA5E9), foreground: .white)
        case "db", "sqlite", "sqlite3": FileBadge(label: "DB", background: Color(hex: 0x0EA5E9), foreground: .white)
        case "ini", "conf", "cfg": FileBadge(label: "CFG", background: Color(hex: 0x6B7280), foreground: .white)
        case "toml": FileBadge(label: "TOML", background: Color(hex: 0x0F766E), foreground: .white)
        case "env": FileBadge(label: "ENV", background: Color(hex: 0x059669), foreground: .white)
        case "svg": FileBadge(label: "SVG", background: Color(hex: 0x8B5CF6), foreground: .white)
        case "ttf", "otf", "woff", "woff2": FileBadge(
                label: "FONT",
                background: Color(hex: 0x9CA3AF),
                foreground: Color(hex: 0x111827)
            )
        case "lock": FileBadge(label: "LOCK", background: Color(hex: 0x6B7280), foreground: .white)
        case "psd": FileBadge(label: "PSD", background: Color(hex: 0x001E36), foreground: Color(hex: 0x00C8FF))
        case "ai": FileBadge(label: "AI", background: Color(hex: 0x300000), foreground: Color(hex: 0xFF9A00))
        case "fig": FileBadge(label: "FIG", background: Color(hex: 0xA259FF), foreground: .white)
        case "sketch": FileBadge(label: "SKETCH", background: Color(hex: 0xFDB300), foreground: Color(hex: 0x111827))
        case "exe": FileBadge(label: "EXE", background: Color(hex: 0x111827), foreground: .white)
        case "msi": FileBadge(label: "MSI", background: Color(hex: 0x0EA5E9), foreground: .white)
        case "apk": FileBadge(label: "APK", background: Color(hex: 0x34D399), foreground: Color(hex: 0x073B3A))
        case "dmg": FileBadge(label: "DMG", background: Color(hex: 0x6B7280), foreground: .white)
        case "pkg": FileBadge(label: "PKG", background: Color(hex: 0xF59E0B), foreground: Color(hex: 0x111827))
        case "deb": FileBadge(label: "DEB", background: Color(hex: 0xCC0000), foreground: .white)
        case "rpm": FileBadge(label: "RPM", background: Color(hex: 0xEE0000), foreground: .white)
        case "log": FileBadge(label: "LOG", background: Color(hex: 0x9CA3AF), foreground: Color(hex: 0x111827))
        case "tmp": FileBadge(label: "TMP", background: Color(hex: 0xD1D5DB), foreground: Color(hex: 0x111827))
        case "bak": FileBadge(label: "BAK", background: Color(hex: 0xD1D5DB), foreground: Color(hex: 0x111827))
        default: nil
        }
    }
}
