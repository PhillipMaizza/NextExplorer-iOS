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
    /// Per-key entries kept for the live grid (a `ready` image is ~0.5 MB). Past this the
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
        /// Being fetched/rendered (or not asked for yet). The cell shows a loading placeholder.
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
    private var inFlight: Set<String> = []

    init() {}

    /// Whether `item` gets a drawn first page: a PDF, or a document Quick Look can draw, within its
    /// kind's size cap. One rule for every list row and grid tile.
    nonisolated static func isEligible(_ item: FileItem) -> Bool {
        if item.isPDF {
            return item.size <= Constants.maxPDFBytes
        }
        guard item.isOfficeDocument || Constants.quickLookKinds.contains(item.kind.lowercased()) else {
            return false
        }
        // A search hit reports no size, so nothing would hold its download to the cap.
        return item.size > 0 && item.size <= Constants.maxQuickLookBytes
    }

    /// Drops every entry, so no drawn page outlives a session. Loads still running land in
    /// entries nothing shows any more.
    func removeAll() {
        entries.removeAll()
        order.removeAll()
        inFlight.removeAll()
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
        now: Date
    ) -> Task<Void, Never>? {
        switch entry.state {
        case .ready, .unavailable: return nil
        case .loading: break
        }
        guard !inFlight.contains(key) else { return nil }

        guard Self.isEligible(item) else {
            entry.state = .unavailable
            return nil
        }
        inFlight.insert(key)

        return Task(priority: Constants.fetchPriority) { [weak self] in
            defer { self?.inFlight.remove(key) }
            // A PDF just shared into the app has its first page seeded from the local copy: the
            // same render, without downloading the file.
            let seeded = await SeededThumbnail.image(
                from: localThumbnails, path: item.id, size: item.size, modified: item.dateModified,
                maxPixel: Constants.renderPixel, priority: Constants.fetchPriority, now: now
            )
            if let seeded {
                entry.state = .ready(seeded)
                return
            }
            // The server previews only media and PDFs; any other document comes down raw.
            let fetch = item.isPDF ? filesClient.previewFileLowPriority : filesClient.downloadRawFileLowPriority
            guard let fileURL = try? await fetch(serverURL, item) else {
                // Cancelled or a transient network failure: leave the entry in `loading` so
                // the next appearance of a cell with this key tries again.
                return
            }
            if let image = await cache.firstPageImage(key, Constants.renderPixel, fileURL) {
                entry.state = .ready(image)
            } else {
                // Downloaded, but nothing could draw it: it won't get better on a retry.
                entry.state = .unavailable
            }
        }
    }
}
