import CoreModels
import FilesClient
import Foundation

/// Warms the offline directory cache in the background: given a set of folder paths, it
/// refreshes each one it hasn't seen recently, a few at a time, over the low priority
/// session. Used for depth 1 prefetch of a folder's subfolders and for refreshing favorited
/// folders when the browse tab loads.
enum DirectoryPrefetch {
    /// A folder cached more recently than this is left alone; the interactive fetch that
    /// happens when the user actually opens it is fresh enough.
    static let freshnessWindow: TimeInterval = 15 * secondsPerMinute
    static let maxConcurrent = 3
    private static let secondsPerMinute: TimeInterval = 60

    /// `paths` arrive in priority order. The folders cached recently are dropped first and `limit`
    /// then caps what is left, so fresh folders never spend the budget.
    static func run(
        paths: [String],
        limit: Int,
        serverURL: URL,
        filesClient: FilesClient,
        directoryCacheStore: DirectoryCacheStore
    ) async {
        // A background cache warm: an approximate freshness check against the wall clock is fine
        // here, so this reads `Date()` directly rather than taking a date dependency.
        let now = Date()
        let stale = Array(paths.filter { path in
            guard !path.isEmpty else { return false }
            guard let writtenAt = directoryCacheStore.lastWrittenAt(serverURL: serverURL, path: path) else { return true }
            return now.timeIntervalSince(writtenAt) >= freshnessWindow
        }.prefix(limit))
        guard !stale.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var iterator = stale.makeIterator()
            for _ in 0 ..< maxConcurrent {
                guard let path = iterator.next() else { break }
                group.addTask { await filesClient.prefetchDirectory(serverURL, path) }
            }
            while await group.next() != nil {
                guard let path = iterator.next() else { continue }
                group.addTask { await filesClient.prefetchDirectory(serverURL, path) }
            }
        }
    }
}
