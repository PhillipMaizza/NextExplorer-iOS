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
    var favorites: IdentifiedArrayOf<Favorite> = []
    var onOpen: (OfflinePinnedRoot) -> Void = { _ in }
    @Shared(.inMemory(OfflineDownloadProgress.sharedKey)) private var progress = OfflineDownloadProgress()

    var body: some View {
        Section {
            if progress.phase == .waitingForNetwork {
                Text(L10n.Offline.waitingForNetwork)
                    .type(.body3(.regular), style: .secondary)
            }
            ForEach(Array(usages.enumerated()), id: \.element.id) { index, usage in
                OfflineManageRow(
                    usage: usage,
                    isFirst: index == 0,
                    isLast: index == usages.count - 1,
                    onOpen: { onOpen(usage.root) },
                    favorite: favorites.first { $0.path == usage.root.path }
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
