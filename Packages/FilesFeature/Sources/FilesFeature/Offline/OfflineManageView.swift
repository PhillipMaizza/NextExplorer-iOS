import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// The "Manage Offline Files" screen: one row per pinned root with its size and a swipe-to-remove.
struct OfflineManageView: View {
    @Bindable var store: StoreOf<OfflineManageFeature>

    var body: some View {
        Group {
            if store.isEmpty {
                EmptyStateView(icon: IconKit.availableOffline, message: L10n.Offline.manageEmpty)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DSGroupedList {
                    Section {
                        ForEach(Array(store.usages.enumerated()), id: \.element.id) { index, usage in
                            OfflineManageRow(
                                usage: usage,
                                isFirst: index == 0,
                                isLast: index == store.usages.count - 1
                            ) {
                                store.send(.removeTapped(path: usage.root.path), animation: .default)
                            }
                        }
                    } footer: {
                        Text(L10n.Offline.available(FileSizeFormat.string(store.totalBytes)))
                            .type(.body3(.regular), style: .tertiary)
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .backgroundGradient()
        .navigationTitle(L10n.Offline.manageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { store.send(.onAppear) }
        .offlineRemovalAlert(
            store.removal,
            onConfirm: { store.send(.removeConfirmed) },
            onCancel: { store.send(.removeCancelled) }
        )
    }
}

struct OfflineManageRow: View {
    let usage: OfflinePinnedRootUsage
    var isFirst = false
    var isLast = false
    /// Tapping the row opens it; nil where rows only list (Manage Offline Files).
    var onOpen: (() -> Void)?
    var favorite: Favorite?
    var syncState = OfflineSyncState.upToDate
    let onRemove: () -> Void

    private var subtitle: String {
        let size = FileSizeFormat.string(usage.sizeBytes)
        let parent = usage.parentPath
        let parts = [size, parent.isEmpty ? nil : parent, syncState.title].compactMap(\.self)
        return parts.joined(separator: " \u{2022} ")
    }

    private var removeButton: some View {
        // No destructive role: it animates the row away on swipe, before the confirmation is answered.
        Button(action: onRemove) {
            Label { Text(L10n.Common.remove) } icon: { IconKit.delete }
        }
        .tint(.negative)
    }

    /// The same row as Browse, Favorites and the saved downloads (`FileRowView` in their list shell), so
    /// a pinned favorite folder keeps the icon and color of its favorite and every other row reads alike.
    var body: some View {
        SelectableListRow(
            isSelecting: false,
            isSelected: false,
            isFirst: isFirst,
            isLast: isLast,
            onTap: { onOpen?() }
        ) {
            FileRowView(
                name: usage.displayName,
                isDirectory: usage.root.isDirectory,
                subtitle: subtitle,
                kind: usage.kind,
                customIcon: favorite.map { FavoriteIcon.symbol(for: $0.icon) },
                customIconTint: favorite.flatMap { FavoriteColor.resolve($0.color) },
                customIconFilled: favorite.map { FavoriteIcon.isFilled($0.icon) } ?? false
            )
        } trailingSwipe: {
            removeButton
        } contextMenu: {
            removeButton
        }
    }
}

#Preview("Manage") {
    NavigationStack {
        OfflineManageView(
            store: Store(
                initialState: {
                    var state = OfflineManageFeature.State()
                    state.usages = [
                        OfflinePinnedRootUsage(
                            root: OfflinePinnedRoot(path: "Documents", isDirectory: true),
                            sizeBytes: 45_000_000
                        ),
                        OfflinePinnedRootUsage(
                            root: OfflinePinnedRoot(path: "Photos/trip.jpg", isDirectory: false),
                            sizeBytes: 3_200_000
                        ),
                    ]
                    return state
                }()
            ) {
                OfflineManageFeature()
            }
        )
    }
}
