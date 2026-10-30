#if os(macOS)
    import ComposableArchitecture
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    private enum Metrics {
        static let padding: CGFloat = .space24
        static let sizeColumnWidth: CGFloat = 90
    }

    /// Manage Offline Files on the Mac: every item kept offline in a table, removed with the
    /// minus button, Delete or the context menu.
    struct MacOfflineManagePane: View {
        let store: StoreOf<OfflineManageFeature>
        @State private var selection: Set<OfflinePinnedRootUsage.ID> = []

        var body: some View {
            VStack(alignment: .leading, spacing: .space12) {
                VStack(spacing: 0) {
                    table
                    Divider()
                    HStack(spacing: 0) {
                        MacTableBarButton(icon: IconKit.minus, label: L10n.Common.remove) { removeSelection() }
                            .disabled(selection.isEmpty)
                        Spacer()
                    }
                    .padding(.horizontal, .space4)
                    .padding(.vertical, .space2)
                }
                .border(Color(nsColor: .separatorColor))
                MacSettingsNote(L10n.Offline.available(FileSizeFormat.string(store.totalBytes)))
            }
            .padding(Metrics.padding)
            .navigationTitle(L10n.Offline.manageTitle)
            .task { store.send(.onAppear) }
        }

        private var table: some View {
            Table(store.usages, selection: $selection) {
                TableColumn(L10n.Sort.name) { usage in
                    MacItemLabel(name: Self.name(usage), isDirectory: usage.root.isDirectory)
                }
                TableColumn(L10n.FileInfo.rowLocation) { usage in
                    Text(usage.root.path).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
                TableColumn(L10n.Sort.size) { usage in
                    Text(FileSizeFormat.string(usage.sizeBytes))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .width(Metrics.sizeColumnWidth)
            }
            .contextMenu(forSelectionType: OfflinePinnedRootUsage.ID.self) { ids in
                Button(L10n.Common.remove, role: .destructive) { remove(ids) }
            }
            .onDeleteCommand { removeSelection() }
            .overlay {
                if store.isEmpty {
                    Text(L10n.Offline.manageEmpty).foregroundStyle(.secondary)
                }
            }
        }

        private func removeSelection() {
            remove(selection)
            selection = []
        }

        private func remove(_ ids: Set<OfflinePinnedRootUsage.ID>) {
            for id in ids {
                if let usage = store.usages[id: id] {
                    store.send(.removeTapped(path: usage.root.path), animation: .default)
                }
            }
        }

        private static func name(_ usage: OfflinePinnedRootUsage) -> String {
            let last = (usage.root.path as NSString).lastPathComponent
            return last.isEmpty ? usage.root.path : last
        }
    }

    #Preview("Items") {
        var state = OfflineManageFeature.State()
        state.usages = [
            OfflinePinnedRootUsage(root: OfflinePinnedRoot(path: "Documents", isDirectory: true), sizeBytes: 45_000_000),
            OfflinePinnedRootUsage(root: OfflinePinnedRoot(path: "Photos/trip.jpg", isDirectory: false), sizeBytes: 3_200_000),
        ]
        return MacOfflineManagePane(store: Store(initialState: state) { OfflineManageFeature() })
            .previewCanvas(.settingsPane)
    }

    #Preview("Empty") {
        MacOfflineManagePane(store: Store(initialState: OfflineManageFeature.State()) { OfflineManageFeature() })
            .previewCanvas(.settingsPane)
    }
#endif
