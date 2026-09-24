import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Foundation
#if os(iOS)
    import UIKit
#endif

private enum Constants {
    /// Don't fetch or rasterize page one of PDFs past this size — a huge scanned document
    /// isn't worth the bandwidth or the render cost for a list thumbnail.
    static let maxSourceBytes: Int64 = 40 * 1_024 * 1_024
    /// Longest side of the render, in pixels. Sized for the biggest grid cell at ~3x, no
    /// more — these are list thumbnails, and every extra pixel is ~4 bytes per image held.
    static let renderPixel: CGFloat = 320
    /// The fetch runs at this priority so it yields to whatever the user is interacting with.
    static let fetchPriority: TaskPriority = .utility
    /// Per-key entries kept for the live grid (a `ready` image is ~0.5 MB). Past this the
    /// oldest are dropped; they re-resolve fast from `PDFThumbnailCache`'s disk layer.
    static let retainedKeyCount = 60
}

/// Process-wide store of PDF first-page thumbnails, keyed by `PDFThumbnailCache.cacheKey`.
///
/// Each key gets an `Entry` — a tiny `@Observable` box holding just that key's `State`. A
/// cell observes only its own entry, so one thumbnail resolving redraws one cell, not the
/// whole visible grid.
///
/// The store itself is deliberately NOT `@Observable`: `entry(forKey:)` mutates the backing
/// dictionary, and if that were observed every such call would invalidate every cell.
///
/// `load` runs the fetch + render in a standalone `Task` that a scroll or navigation does
/// not cancel, so revisiting a folder finds the work already done or still progressing.
@MainActor
final class PDFThumbnailStore {
    static let shared = PDFThumbnailStore()

    enum State {
        /// Being fetched/rendered (or not asked for yet). The cell shows a loading placeholder.
        case loading
        case ready(PlatformImage)
        /// Too large, or fetched but not a readable PDF. The cell shows the plain PDF icon.
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

    func load(
        entry: Entry,
        key: String,
        item: FileItem,
        serverURL: URL,
        filesClient: FilesClient,
        cache: PDFThumbnailCache
    ) {
        switch entry.state {
        case .ready, .unavailable: return
        case .loading: break
        }
        guard !inFlight.contains(key) else { return }

        guard item.size <= Constants.maxSourceBytes else {
            entry.state = .unavailable
            return
        }
        inFlight.insert(key)

        Task(priority: Constants.fetchPriority) { [weak self] in
            defer { self?.inFlight.remove(key) }
            guard let pdfURL = try? await filesClient.previewFileLowPriority(serverURL, item) else {
                // Cancelled or a transient network failure — leave the entry in `loading` so
                // the next appearance of a cell with this key tries again.
                return
            }
            if let image = await cache.firstPageImage(key, Constants.renderPixel, pdfURL) {
                entry.state = .ready(image)
            } else {
                // Downloaded, but PDFKit couldn't open it — it won't get better on a retry.
                entry.state = .unavailable
            }
        }
    }
}
