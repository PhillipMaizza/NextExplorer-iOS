import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

private enum Constants {
    static let rowIconSize: CGFloat = .iconMedium

    @MainActor static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

/// The "Manage Offline Files" screen: one row per pinned root with its size and a swipe-to-remove.
struct OfflineManageView: View {
    @Bindable var store: StoreOf<OfflineManageFeature>

    var body: some View {
        Group {
            if store.isEmpty {
                EmptyStateView(icon: IconKit.cloud, message: L10n.Offline.manageEmpty)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(store.usages) { usage in
                            OfflineManageRow(usage: usage) {
                                store.send(.removeTapped(path: usage.root.path), animation: .default)
                            }
                        }
                    } footer: {
                        Text(L10n.Offline.available(Constants.byteFormatter.string(fromByteCount: store.totalBytes)))
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
    }
}

private struct OfflineManageRow: View {
    let usage: OfflinePinnedRootUsage
    let onRemove: () -> Void

    private var name: String {
        let last = (usage.root.path as NSString).lastPathComponent
        return last.isEmpty ? usage.root.path : last
    }

    var body: some View {
        HStack(spacing: .space12) {
            (usage.root.isDirectory ? IconKit.folder : IconKit.document)
                .resizable()
                .scaledToFit()
                .foregroundStyle(usage.root.isDirectory ? Color.accent : Color.secondaryDS)
                .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
            VStack(alignment: .leading, spacing: .space2) {
                Text(name)
                    .type(.body2(.regular), style: .primaryOnSurface)
                    .lineLimit(1)
                if !usage.root.path.isEmpty {
                    Text(usage.root.path)
                        .type(.body3(.regular), style: .secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer()
            Text(Constants.byteFormatter.string(fromByteCount: usage.sizeBytes))
                .type(.body3(.regular), style: .tertiary)
                .monospacedDigit()
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onRemove) {
                Label(L10n.Common.remove, systemImage: "trash")
            }
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
                        OfflinePinnedRootUsage(root: OfflinePinnedRoot(path: "Documents", isDirectory: true), sizeBytes: 45_000_000),
                        OfflinePinnedRootUsage(root: OfflinePinnedRoot(path: "Photos/trip.jpg", isDirectory: false), sizeBytes: 3_200_000),
                    ]
                    return state
                }()
            ) {
                OfflineManageFeature()
            }
        )
    }
}
