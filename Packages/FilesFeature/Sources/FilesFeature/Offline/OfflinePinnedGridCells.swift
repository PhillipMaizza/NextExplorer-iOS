import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// The Offline tab's pinned items as grid tiles: a folder opens, a file only shows what is kept, and
/// the context menu removes the pin (after the usual confirmation).
struct OfflinePinnedGridCells: View {
    let store: StoreOf<OfflineManageFeature>
    let usages: [OfflinePinnedRootUsage]
    var favorites: IdentifiedArrayOf<Favorite> = []
    var onOpenFolder: (String) -> Void = { _ in }
    @AppStorage(AppStorageKeys.thumbnailSize) private var thumbnailSizeRaw = ThumbnailSize.medium.rawValue

    var body: some View {
        ForEach(usages) { usage in
            let favorite = favorites.first { $0.path == usage.root.path }
            SelectableGridCell(
                isSelecting: false,
                isSelected: false,
                onTap: {
                    if usage.root.isDirectory {
                        onOpenFolder(usage.root.path)
                    }
                }
            ) {
                GridCellView(
                    name: usage.displayName,
                    isDirectory: usage.root.isDirectory,
                    kind: usage.kind,
                    iconSize: (ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium).iconSize,
                    customIcon: usage.root.isDirectory ? favorite.map { FavoriteIcon.symbol(for: $0.icon) } : nil,
                    customIconTint: favorite.flatMap { FavoriteColor.resolve($0.color) },
                    customIconFilled: favorite.map { FavoriteIcon.isFilled($0.icon) } ?? false
                )
            } contextMenu: {
                Button {
                    store.send(.removeTapped(path: usage.root.path), animation: .default)
                } label: {
                    Label { Text(L10n.Common.remove) } icon: { IconKit.delete }
                }
                .tint(.negative)
            }
        }
    }
}
