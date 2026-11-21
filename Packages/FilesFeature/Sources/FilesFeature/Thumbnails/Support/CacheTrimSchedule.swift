import FilesClient
import Foundation
import Synchronization

/// Counts the thumbnail and PDF page files written into the preview cache. Only a preview download
/// runs the cache's own eviction, so a user who scrolls grids and never opens a file would grow it
/// without bound; every `interval` writes the cache is trimmed back under its cap off the caller.
final class CacheTrimSchedule: Sendable {
    private enum Constants {
        static let liveInterval = 200
    }

    static let shared = CacheTrimSchedule(every: Constants.liveInterval)

    private let interval: Int
    private let writes = Mutex(0)

    init(every interval: Int) {
        self.interval = interval
    }

    /// Records one write and answers whether the cache is due a trim now.
    func recordWrite() -> Bool {
        writes.withLock { count in
            count += 1
            guard count >= interval else { return false }
            count = 0
            return true
        }
    }

    func recordWriteAndTrimIfDue() {
        guard recordWrite() else { return }
        Task.detached(priority: .background) {
            CacheAccountScope.trimPreviewCache()
        }
    }
}
