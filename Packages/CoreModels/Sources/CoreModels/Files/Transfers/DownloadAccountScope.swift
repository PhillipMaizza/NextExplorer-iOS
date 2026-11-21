import Foundation

public enum DownloadAccountScope {
    /// `@Shared(.inMemory(...))` key holding the current session's scope identifier.
    public static let sharedKey = "downloadAccountScope"

    public static func identifier(serverURL: URL, userID: String) -> String {
        let raw = serverURL.absoluteString + "\n" + userID
        return raw.sha256Hex(byteCount: 16)
    }
}
