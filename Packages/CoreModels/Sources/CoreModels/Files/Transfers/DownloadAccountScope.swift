import Foundation

/// A stable per account folder name for locally saved downloads, so two accounts on the same
/// device (even the same server) never see each other's files. Derived from the server URL and
/// the user id, hashed to a filesystem safe hex string. Published process wide through
/// `@Shared(.inMemory(sharedKey))`, set when a session begins and cleared on sign out; an empty
/// value means "no session", which the download store maps to the unscoped legacy folder.
public enum DownloadAccountScope {
    /// `@Shared(.inMemory(...))` key holding the current session's scope identifier.
    public static let sharedKey = "downloadAccountScope"

    public static func identifier(serverURL: URL, userID: String) -> String {
        let raw = serverURL.absoluteString + "\n" + userID
        return raw.sha256Hex(byteCount: 16)
    }
}
