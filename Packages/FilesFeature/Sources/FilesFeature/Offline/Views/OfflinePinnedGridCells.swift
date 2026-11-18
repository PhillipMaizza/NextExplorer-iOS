import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// The Offline tab's pinned items as grid tiles: a folder opens in place, a file in a preview from its
/// kept copy, and the context menu removes the pin (after the usual confirmation).
struct OfflinePinnedGridCells: View {
    let store: StoreOf<OfflineManageFeature>
    var usages: [OfflinePinnedRootUsage]
    var favorites: IdentifiedArrayOf<Favorite> = []
    var serverURL: URL?
    var showThumbnails = false
    var isSelecting = false
    var selectedPaths: Set<String> = []
    /// The tab's preview zoom, so a kept file grows from its tile when opened.
    var zoom: PreviewZoomContext?
    var onOpen: (OfflinePinnedRoot) -> Void = { _ in }

    var body: some View {
        ForEach(usages) { usage in
            let favorite = favorites.first { $0.path == usage.root.path }
            SelectableGridCell(
                selectionID: OfflineTabSweepID.pinned(usage.root.path),
                isSelecting: isSelecting,
                isSelected: selectedPaths.contains(usage.root.path),
                onTap: { onOpen(usage.root) }
            ) {
                GridCellView(
                    name: usage.displayName,
                    isDirectory: usage.root.isDirectory,
                    kind: usage.kind,
                    size: usage.sizeBytes,
                    thumbnailFile: usage.thumbnailFile,
                    serverURL: serverURL,
                    showThumbnails: showThumbnails,
                    customIcon: usage.root.isDirectory ? favorite.map { FavoriteIcon.symbol(for: $0.icon) } : nil,
                    customIconTint: favorite.flatMap { FavoriteColor.resolve($0.color) },
                    customIconFilled: favorite.map { FavoriteIcon.isFilled($0.icon) } ?? false,
                    matchedSource: usage.root.isDirectory ? nil : zoom?.source(for: usage.root.path)
                )
            } contextMenu: {
                if !isSelecting {
                    Button {
                        store.send(.removeTapped(path: usage.root.path), animation: DSMotion.listDiff)
                    } label: {
                        Label { Text(L10n.Common.remove) } icon: { IconKit.delete }
                    }
                    .tint(.negative)
                }
            }
        }
    }
}

/// The Offline tab's grid: pinned folders as cards first, then pinned files followed by `trailing`
/// (the tab's downloads), each in its own `FileGrid` so folders and files take their own columns.
struct OfflinePinnedGrid<Trailing: View>: View {
    let cells: OfflinePinnedGridCells
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        let folders = cells(isDirectory: true)
        if !folders.usages.isEmpty {
            FileGrid(.folders) {
                folders
            }
        }
        FileGrid {
            cells(isDirectory: false)
            trailing()
        }
    }

    private func cells(isDirectory: Bool) -> OfflinePinnedGridCells {
        var subset = cells
        subset.usages = cells.usages.filter { $0.root.isDirectory == isDirectory }
        return subset
    }
}

#Preview("Pinned folders and files") {
    ScrollView {
        VStack(spacing: .space24) {
            OfflinePinnedGrid(
                cells: OfflinePinnedGridCells(
                    store: Store(initialState: OfflineManageFeature.State()) { OfflineManageFeature() },
                    usages: [
                        OfflinePinnedRootUsage(
                            root: OfflinePinnedRoot(path: "Documents", isDirectory: true),
                            sizeBytes: 45_000_000
                        ),
                        OfflinePinnedRootUsage(
                            root: OfflinePinnedRoot(path: "notes.txt", isDirectory: false),
                            sizeBytes: 1_200
                        ),
                    ]
                )
            ) {
                EmptyView()
            }
        }
        .padding(FileGridMetrics.margin)
    }
}
