import CoreModels
import DesignSystem
import SwiftUI

extension FileItem {
    /// The colour the web client dedicates to an extension, as raw hex to match it exactly rather
    /// than deriving semantic colours for about 50 one off brand colours: a `.py` file is the same
    /// shade of blue here as on the web.
    static func kindColor(forKind kind: String) -> Color? {
        switch kind.lowercased() {
        case "pdf": Color(hex: 0xE81123)
        case "doc", "docx", "rtf": Color(hex: 0x2563EB)
        case "xls", "xlsx": Color(hex: 0x16A34A)
        case "ppt", "pptx": Color(hex: 0xF97316)
        case "csv": Color(hex: 0x22C55E)
        case "txt": Color(hex: 0x6B7280)
        case "md", "markdown": Color(hex: 0x0EA5E9)
        case "html", "htm": Color(hex: 0xE44D26)
        case "gsheet": Color(hex: 0x188038)
        case "gdoc": Color(hex: 0x1A73E8)
        case "gslides": Color(hex: 0xF9AB00)
        case "gform": Color(hex: 0x7627BB)
        case "gdraw": Color(hex: 0xEA4335)
        case "css": Color(hex: 0x2965F1)
        case "scss": Color(hex: 0xC6538C)
        case "less": Color(hex: 0x1D365D)
        case "js": Color(hex: 0xF7DF1E)
        case "ts": Color(hex: 0x3178C6)
        case "jsx": Color(hex: 0x61DAFB)
        case "tsx": Color(hex: 0x3178C6)
        case "vue": Color(hex: 0x41B883)
        case "json": Color(hex: 0x8B5CF6)
        case "yml", "yaml": Color(hex: 0x14B8A6)
        case "xml": Color(hex: 0xEC4899)
        case "sh", "bash", "zsh": Color(hex: 0x374151)
        case "py": Color(hex: 0x3776AB)
        case "rb": Color(hex: 0xCC342D)
        case "php": Color(hex: 0x777BB4)
        case "go": Color(hex: 0x00ADD8)
        case "rs": Color(hex: 0xDEA584)
        case "java": Color(hex: 0xE11D48)
        case "kt", "kts": Color(hex: 0x7F52FF)
        case "swift": Color(hex: 0xFA7343)
        case "c": Color(hex: 0x5C6BC0)
        case "cpp", "cc", "cxx": Color(hex: 0x00599C)
        case "cs": Color(hex: 0x239120)
        case "sql": Color(hex: 0x0EA5E9)
        case "db", "sqlite", "sqlite3": Color(hex: 0x0EA5E9)
        case "ini", "conf", "cfg": Color(hex: 0x6B7280)
        case "toml": Color(hex: 0x0F766E)
        case "env": Color(hex: 0x059669)
        case "svg": Color(hex: 0x8B5CF6)
        case "ttf", "otf", "woff", "woff2": Color(hex: 0x9CA3AF)
        case "lock": Color(hex: 0x6B7280)
        case "psd": Color(hex: 0x001E36)
        case "ai": Color(hex: 0x300000)
        case "fig": Color(hex: 0xA259FF)
        case "sketch": Color(hex: 0xFDB300)
        case "exe": Color(hex: 0x111827)
        case "msi": Color(hex: 0x0EA5E9)
        case "apk": Color(hex: 0x34D399)
        case "dmg": Color(hex: 0x6B7280)
        case "pkg": Color(hex: 0xF59E0B)
        case "deb": Color(hex: 0xCC0000)
        case "rpm": Color(hex: 0xEE0000)
        case "log": Color(hex: 0x9CA3AF)
        case "tmp": Color(hex: 0xD1D5DB)
        case "bak": Color(hex: 0xD1D5DB)
        default: nil
        }
    }
}
