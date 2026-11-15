import ComposableArchitecture
import SwiftUI

/// What a slide across the Offline tab knows each item by: pinned items and saved files share one
/// sweep, so their ids are kept apart.
enum OfflineTabSweepID {
    private static let pinnedPrefix = "pinned:"
    private static let downloadPrefix = "saved:"

    static func pinned(_ path: String) -> String {
        pinnedPrefix + path
    }

    static func download(_ id: LocalDownload.ID) -> String {
        downloadPrefix + id
    }

    /// Splits a swept selection back into pinned paths and saved file ids.
    static func split(_ ids: Set<String>) -> (pinnedPaths: Set<String>, downloadIDs: Set<LocalDownload.ID>) {
        (
            Set(ids.compactMap { $0.hasPrefix(pinnedPrefix) ? String($0.dropFirst(pinnedPrefix.count)) : nil }),
            Set(ids.compactMap { $0.hasPrefix(downloadPrefix) ? String($0.dropFirst(downloadPrefix.count)) : nil })
        )
    }
}

/// The Offline tab swept by a finger in select mode: the pinned items, then the saved files, as shown.
struct OfflineTabDragToSelect: ViewModifier {
    let store: StoreOf<OfflineTabFeature>
    let pinnedPaths: [String]

    private var selection: Set<String> {
        Set(store.selectedPinnedPaths.map(OfflineTabSweepID.pinned))
            .union(store.selectedDownloadIDs.map(OfflineTabSweepID.download))
    }

    func body(content: Content) -> some View {
        content.dragToSelect(
            isEnabled: store.isSelecting,
            selection: selection,
            order: { [pinnedPaths] in
                pinnedPaths.map(OfflineTabSweepID.pinned)
                    + store.displayedDownloads.map { OfflineTabSweepID.download($0.id) }
            },
            onChange: { ids in
                let split = OfflineTabSweepID.split(ids)
                store.send(.selectionSwept(pinnedPaths: split.pinnedPaths, downloadIDs: split.downloadIDs))
            }
        )
    }
}
