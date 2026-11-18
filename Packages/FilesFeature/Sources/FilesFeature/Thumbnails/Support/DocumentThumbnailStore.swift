import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Foundation
import ShareUploads
#if os(iOS)
    import UIKit
#endif

private enum Constants {
    /// Don't fetch or rasterize page one of PDFs past this size: a huge scanned document
    /// isn't worth the bandwidth or the render cost for a list thumbnail.
    static let maxPDFBytes: Int64 = 40 * 1_024 * 1_024
    /// Other documents are downloaded whole for Quick Look to draw, so they get a tighter cap.
    static let maxQuickLookBytes: Int64 = 10 * 1_024 * 1_024
    /// Kinds Quick Look draws beside the Office documents the app opens.
    static let quickLookKinds: Set<String> = ["pages", "numbers", "epub", "usdz", "ttf", "otf"]
    /// Longest side of the render, in pixels. Sized for the biggest grid cell at ~3x, no
    /// more: these are list thumbnails, and every extra pixel is ~4 bytes per image held.
    static let renderPixel: CGFloat = 320
    /// The fetch runs at this priority so it yields to whatever the user is interacting with.
    static let fetchPriority: TaskPriority = .utility
    /// Per key entries kept for the live grid (a `ready` image is ~0.5 MB). Past this the
    /// oldest are dropped; they resolve again fast from `DocumentThumbnailCache`'s disk layer.
    static let retainedKeyCount = 60
}

/// Process wide store of document first page thumbnails, keyed by `DocumentThumbnailCache.cacheKey`.
///
/// Each key gets an `Entry`: a tiny `@Observable` box holding just that key's `State`. A
/// cell observes only its own entry, so one thumbnail resolving redraws one cell, not the
/// whole visible grid.
///
/// The store itself is deliberately NOT `@Observable`: `entry(forKey:)` mutates the backing
/// dictionary, and if that were observed every such call would invalidate every cell.
///
/// `load` runs the fetch + render in a standalone `Task` that a scroll or navigation does
/// not cancel, so revisiting a folder finds the work already done or still progressing.
@MainActor
final class DocumentThumbnailStore {
    static let shared = DocumentThumbnailStore()

    enum State {
        /// Being fetched/rendered, not asked for yet, or not downloaded on a metered network (its
        /// next appearance asks again). The cell shows the kind's icon.
        case loading
        case ready(PlatformImage)
        /// Too large, or fetched but nothing could draw it. The cell shows the kind's icon.
        case unavailable

        var isReady: Bool {
            if case .ready = self {
                return true
            }
            return false
        }
    }

    @MainActor
    @Observable
    final class Entry {
        var state: State = .loading
    }

    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var tasks: [String: Task<Void, Never>] = [:]

    init() {}

    /// Whether `item` gets a drawn first page: a PDF, or a document Quick Look can draw, within its
    /// kind's size cap. One rule for every list row and grid tile.
    nonisolated static func isEligible(_ item: FileItem) -> Bool {
        // A search hit reports no size, so nothing would hold its download to the cap.
        guard item.size > 0 else {
            return false
        }
        if item.isPDF {
            return item.size <= Constants.maxPDFBytes
        }
        guard item.isOfficeDocument || Constants.quickLookKinds.contains(item.kind.lowercased()) else {
            return false
        }
        return item.size <= Constants.maxQuickLookBytes
    }

    /// Drops every entry and stops every load still running, so no drawn page outlives a session.
    func removeAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        entries.removeAll()
        order.removeAll()
    }

    func entry(forKey key: String) -> Entry {
        if let existing = entries[key] {
            return existing
        }
        let entry = Entry()
        entries[key] = entry
        order.append(key)
        while order.count > Constants.retainedKeyCount {
            entries.removeValue(forKey: order.removeFirst())
        }
        return entry
    }

    @discardableResult
    func load(
        entry: Entry,
        key: String,
        item: FileItem,
        serverURL: URL,
        filesClient: FilesClient,
        cache: DocumentThumbnailCache,
        localThumbnails: LocalThumbnailStore,
        offlineFiles: OfflineFileStore,
        now: Date,
        isMetered: Bool = false,
        scope: String = CacheAccountScope.current
    ) -> Task<Void, Never>? {
        switch entry.state {
        case .ready, .unavailable: return nil
        case .loading: break
        }
        guard tasks[key] == nil else { return nil }

        guard Self.isEligible(item) else {
            entry.state = .unavailable
            return nil
        }
        // Read as the load starts: after a wipe or an account switch it neither fetches with the next
        // account's session nor draws into the cache.
        let wipeStamp = CacheAccountScope.wipeStamp(scope)
        let task = Task(priority: Constants.fetchPriority) { [weak self] in
            // A cancelled load was already dropped by `removeAll`, and a newer one may hold its key.
            defer {
                if !Task.isCancelled {
                    self?.tasks[key] = nil
                }
            }
            // An entry dropped past the cap and taken again by its cell gets the result, not the dropped box.
            @MainActor func publish(_ state: State) {
                (self?.entries[key] ?? entry).state = state
            }
            func isStale() -> Bool {
                CacheAccountScope.current != scope || CacheAccountScope.wipeStamp(scope) != wipeStamp
            }
            func draw(_ fileURL: URL?) async -> PlatformImage? {
                await CacheAccountScope.withPinned(scope) {
                    await cache.firstPageImage(key, Constants.renderPixel, fileURL)
                }
            }
            // A PDF just shared into the app has its first page seeded from the local copy: the
            // same render, without downloading the file.
            let seeded = await SeededThumbnail.image(
                from: localThumbnails, path: item.id, size: item.size, modified: item.dateModified,
                maxPixel: Constants.renderPixel, priority: Constants.fetchPriority, now: now
            )
            if let seeded {
                publish(.ready(seeded))
                return
            }
            // On mobile data nothing is downloaded just to draw a thumbnail: a kept copy is drawn
            // from disk, anything else shows only a page drawn before.
            if isMetered {
                let kept = await Task.detached(priority: Constants.fetchPriority) { offlineFiles.localURL(item) }.value
                guard !isStale() else {
                    return
                }
                if let image = await draw(kept) {
                    publish(.ready(image))
                } else if kept != nil {
                    publish(.unavailable)
                }
                return
            }
            guard !isStale() else {
                return
            }
            // The server previews only media and PDFs; any other document comes down raw.
            let fetch = item.isPDF ? filesClient.previewFileLowPriority : filesClient.downloadRawFileLowPriority
            guard let fileURL = try? await fetch(serverURL, item) else {
                // Cancelled or a transient network failure: leave the entry in `loading` so
                // the next appearance of a cell with this key tries again.
                return
            }
            guard !isStale() else {
                return
            }
            if let image = await draw(fileURL) {
                publish(.ready(image))
            } else {
                // Downloaded, but nothing could draw it: it won't get better on a retry.
                publish(.unavailable)
            }
        }
        tasks[key] = task
        return task
    }
}
