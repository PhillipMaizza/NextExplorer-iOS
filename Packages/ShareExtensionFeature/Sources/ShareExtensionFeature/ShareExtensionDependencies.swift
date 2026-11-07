import Dependencies
import FilesClient
import Foundation
import NetworkClient

public extension DirectoryCacheStore {
    /// A store that keeps nothing: every read misses and every write is dropped. The Share
    /// Extension's folder picker browses with it, because the extension's own container sits
    /// outside the app's sign out wipe, so a saved listing there would outlive the account.
    static let noCache = DirectoryCacheStore(
        read: { _, _ in nil },
        lastWrittenAt: { _, _ in nil },
        write: { _, _, _, _, _ in },
        touch: { _, _, _, _ in },
        remove: { _, _ in },
        clearAll: {},
        totalSizeBytes: { 0 }
    )
}

/// The dependencies the Share Extension runs with that differ from the app's.
public enum ShareExtensionDependencies {
    /// Browsing from the extension (the folder picker, the default folder check) never persists a
    /// directory listing.
    public static func configure(_ values: inout DependencyValues) {
        values.directoryCacheStore = .noCache
        values.filesClient = .live(networkClient: values.networkClient, directoryCacheStore: .noCache)
    }
}
