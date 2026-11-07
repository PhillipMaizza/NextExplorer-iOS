import Foundation

/// Where the disk caches live and how their entries are named, in one place so the stores that
/// write them and the one time cleanup of the entries an older release wrote agree.
public enum CacheLayout {
    /// Under Application Support.
    public static let directoryCacheName = "DirectoryCache"
    public static let listCacheName = "ListCache"
    /// Under Caches.
    public static let previewCacheName = "PreviewCache"
    /// Per item slot directories inside `previewCacheName`.
    public static let previewSlotNamespaces = ["preview", "download"]
    /// Flat directories of account prefixed files inside `previewCacheName`.
    public static let flatScopedDirectories = ["thumbnails", "thumbnail-urls", "pdf-thumbnails"]
}

public extension CacheAccountScope {
    /// Whether `name` starts with an account prefix (`<16 hex>-`), as every entry written since the
    /// caches became account scoped does.
    static func hasAccountPrefix(_ name: String) -> Bool {
        let digits = prefixByteCount * hexDigitsPerByte
        guard name.count > digits, name[name.index(name.startIndex, offsetBy: digits)] == prefixSeparator else { return false }
        return name.prefix(digits).allSatisfy(\.isHexDigit)
    }
}
