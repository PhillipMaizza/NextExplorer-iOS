import AppStorageKeys
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
    let usages: [OfflinePinnedRootUsage]
    var favorites: IdentifiedArrayOf<Favorite> = []
    var serverURL: URL?
    var showThumbnails = false
    var isSelecting = false
    var selectedPaths: Set<String> = []
    /// The tab's preview zoom, so a kept file grows from its tile when opened.
    var zoom: PreviewZoomContext?
    var onOpen: (OfflinePinnedRoot) -> Void = { _ in }
    @AppStorage(AppStorageKeys.thumbnailSize) private var thumbnailSizeRaw = ThumbnailSize.medium.rawValue

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
                    thumbnailFile: usage.thumbnailFile,
                    serverURL: serverURL,
                    showThumbnails: showThumbnails,
                    iconSize: (ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium).iconSize,
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
