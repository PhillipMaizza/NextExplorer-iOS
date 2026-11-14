import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// The Offline tab's block of pinned items: one row per pinned file or folder with its size and a
/// swipe to remove. Live progress is the pill above the tab bar.
struct OfflinePinnedSection: View {
    let store: StoreOf<OfflineManageFeature>
    /// What to list, already filtered and ordered by the tab.
    let usages: [OfflinePinnedRootUsage]
    /// The offline run's phase, which every pinned row's state follows.
    var phase = OfflineDownloadProgress.Phase.idle
    var favorites: IdentifiedArrayOf<Favorite> = []
    var serverURL: URL?
    var showThumbnails = false
    var isSelecting = false
    var selectedPaths: Set<String> = []
    var onOpen: (OfflinePinnedRoot) -> Void = { _ in }

    var body: some View {
        Section {
            if phase == .waitingForNetwork {
                Text(L10n.Offline.waitingForNetwork)
                    .type(.body3(.regular), style: .secondary)
            }
            ForEach(Array(usages.enumerated()), id: \.element.id) { index, usage in
                OfflineManageRow(
                    usage: usage,
                    isFirst: index == 0,
                    isLast: index == usages.count - 1,
                    onOpen: { onOpen(usage.root) },
                    favorite: favorites.first { $0.path == usage.root.path },
                    syncState: OfflineSyncState(phase: phase),
                    serverURL: serverURL,
                    showThumbnails: showThumbnails,
                    isSelecting: isSelecting,
                    isSelected: selectedPaths.contains(usage.root.path)
                ) {
                    store.send(.removeTapped(path: usage.root.path), animation: .default)
                }
            }
        }
    }
}

private let previewUsages = [
    OfflinePinnedRootUsage(
        root: OfflinePinnedRoot(path: "Documents", isDirectory: true),
        sizeBytes: 45_000_000
    ),
    OfflinePinnedRootUsage(
        root: OfflinePinnedRoot(path: "Photos/trip.jpg", isDirectory: false),
        sizeBytes: 3_200_000
    ),
]

#Preview("Pinned") {
    List {
        OfflinePinnedSection(
            store: Store(initialState: OfflineManageFeature.State()) { OfflineManageFeature() },
            usages: previewUsages
        )
    }
}
