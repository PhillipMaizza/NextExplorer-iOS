import Foundation

/// Reduces an untrusted name — a server-supplied `FileItem.name`, a rename a user typed —
/// to a single path component that can't traverse out of the directory it's joined to.
///
/// `URL.appendingPathComponent(_:)` does not standardise its argument, and `FileManager`
/// resolves `..` at write time, so `directory.appendingPathComponent("../../x")` writes
/// outside `directory`. Names are kept human- and extension-readable (QuickLook / WebKit
/// infer the type from the extension) rather than hashed, so this strips any directory
/// portion instead: `"../../Library/Preferences/x.plist"` becomes `"x.plist"`.
public enum SafeFileName {
    /// The sanitised single component, or `fallback` when the input reduces to nothing usable
    /// (empty, `"."`, `".."`, or all separators).
    public static func component(_ rawName: String, fallback: String = "file") -> String {
        // Normalise Windows-style separators too — they're valid filename characters on
        // Apple platforms, so a `\` wouldn't be caught by `lastPathComponent` alone.
        let normalized = rawName.replacingOccurrences(of: "\\", with: "/")
        // `("/" as NSString).lastPathComponent` is `"/"`, not empty — guard it explicitly.
        let base = (normalized as NSString).lastPathComponent
        guard !base.isEmpty, base != ".", base != "..", base != "/" else { return fallback }
        return base
    }

    /// Whether `rawName` is already a safe single component (used to reject a rename outright
    /// rather than silently rewriting it).
    public static func isSafeComponent(_ rawName: String) -> Bool {
        component(rawName, fallback: "\u{0}") == rawName
    }
}
