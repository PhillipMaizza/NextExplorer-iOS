import FilesClient
import Foundation

/// Removes the cache entries an older release wrote before the caches were account scoped. Those
/// files carry no account prefix, so no account wipe can ever reach them: they would sit on disk,
/// holding listings and file bytes of whoever used the app then, until the app is deleted.
public enum LegacyCacheCleanup {
    private enum Constants {
        static let didRunKey = "legacyUnscopedCacheCleanupDidRun"
    }

    /// Runs the cleanup once per install and never again. Safe to call on every launch.
    public static func runIfNeeded() {
        run(defaults: .standard)
    }

    static func run(
        defaults: UserDefaults,
        applicationSupport: URL? = nil,
        caches: URL? = nil,
        fileManager: FileManager = .default
    ) {
        guard !defaults.bool(forKey: Constants.didRunKey) else { return }
        let applicationSupport = applicationSupport ?? directory(.applicationSupportDirectory, fileManager)
        let caches = caches ?? directory(.cachesDirectory, fileManager)
        if let applicationSupport {
            for name in [CacheLayout.directoryCacheName, CacheLayout.listCacheName] {
                removeUnscopedEntries(in: applicationSupport.appendingPathComponent(name, isDirectory: true), fileManager)
            }
        }
        if let caches {
            let previewRoot = caches.appendingPathComponent(CacheLayout.previewCacheName, isDirectory: true)
            for name in CacheLayout.previewSlotNamespaces + CacheLayout.flatScopedDirectories {
                removeUnscopedEntries(in: previewRoot.appendingPathComponent(name, isDirectory: true), fileManager)
            }
        }
        defaults.set(true, forKey: Constants.didRunKey)
    }

    private static func removeUnscopedEntries(in directory: URL, _ fileManager: FileManager) {
        let entries = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where !CacheAccountScope.hasAccountPrefix(entry.lastPathComponent) {
            try? fileManager.removeItem(at: entry)
        }
    }

    private static func directory(_ kind: FileManager.SearchPathDirectory, _ fileManager: FileManager) -> URL? {
        try? fileManager.url(for: kind, in: .userDomainMask, appropriateFor: nil, create: false)
    }
}
