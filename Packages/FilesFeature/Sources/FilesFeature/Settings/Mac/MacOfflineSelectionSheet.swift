#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 620
        static let height: CGFloat = 520
        static let padding: CGFloat = .space16
        static let checkColumnWidth: CGFloat = 28
        static let sizeColumnWidth: CGFloat = 90
        static let alreadyOfflineOpacity: Double = 0.5
    }

    /// Choosing what to keep offline, as a native sheet: a file table with a checkbox per row,
    /// double click to open a folder, Back to go up, and the running size estimate by the
    /// Download button.
    struct MacOfflineSelectionSheet: View {
        let store: StoreOf<OfflineSelectionFeature>
        @State private var highlighted: Set<FileItem.ID> = []

        var body: some View {
            VStack(spacing: 0) {
                header
                Divider()
                table
                Divider()
                footer
            }
            .frame(width: Metrics.width, height: Metrics.height)
            .task { store.send(.onAppear) }
        }

        private var header: some View {
            MacSheetHeader(
                title: L10n.Offline.selectionTitle,
                subtitle: store.directoryPath,
                canGoBack: store.canNavigateBack,
                onBack: { store.send(.backTapped) }
            )
            .padding(Metrics.padding)
        }

        private var table: some View {
            Table(store.items, selection: $highlighted) {
                TableColumn("") { item in
                    let isOffline = store.state.isAlreadyOffline(item)
                    // Named after its row, so VoiceOver says which item the checkbox selects.
                    Toggle(item.name, isOn: Binding(
                        get: { store.state.isSelected(item) || isOffline },
                        set: { _ in store.send(.selectionToggled(item)) }
                    ))
                    .labelsHidden()
                    .disabled(isOffline)
                }
                .width(Metrics.checkColumnWidth)
                TableColumn(L10n.Sort.name) { item in
                    MacItemLabel(name: item.name, isDirectory: item.isDirectory)
                        .opacity(store.state.isAlreadyOffline(item) ? Metrics.alreadyOfflineOpacity : 1)
                }
                TableColumn(L10n.Sort.size) { item in
                    Text(sizeText(item))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .width(Metrics.sizeColumnWidth)
            }
            .contextMenu(forSelectionType: FileItem.ID.self, menu: { _ in }, primaryAction: { ids in
                guard let id = ids.first, let item = store.items[id: id] else { return }
                if item.isDirectory {
                    store.send(.folderTapped(item))
                } else if !store.state.isAlreadyOffline(item) {
                    store.send(.selectionToggled(item))
                }
            })
            .overlay { overlay }
        }

        @ViewBuilder
        private var overlay: some View {
            if store.phase == .loading, store.items.isEmpty {
                MacSpinner()
            } else if let errorMessage = store.phase.errorMessage {
                VStack(spacing: .space8) {
                    Text(errorMessage).foregroundStyle(.secondary)
                    Button(L10n.Common.retry) { store.send(.retryTapped) }
                }
            } else if store.items.isEmpty, store.phase == .loaded {
                Text(L10n.Offline.selectionEmpty).foregroundStyle(.secondary)
            }
        }

        private var footer: some View {
            MacDialogButtons(
                confirmTitle: L10n.Offline.selectionDownload,
                isConfirmEnabled: store.canConfirm && !isOverFreeSpace,
                onCancel: { store.send(.cancelTapped) },
                onConfirm: { store.send(.confirmTapped) }
            ) {
                VStack(alignment: .leading, spacing: .space2) {
                    Text(L10n.MacSettings.labelFormat(L10n.Offline.selectionEstimate) + " " + estimateText)
                        .monospacedDigit()
                    if isOverFreeSpace {
                        Text(L10n.Offline.selectionInsufficientSpace).font(.callout).foregroundStyle(Color.negativeText)
                    }
                }
            }
            .padding(Metrics.padding)
        }

        private func sizeText(_ item: FileItem) -> String {
            if item.isDirectory {
                return store.folderSizes[item.id].map { FileSizeFormat.string($0) } ?? "--"
            }
            return FileSizeFormat.string(item.size)
        }

        private var estimateText: String {
            let size = FileSizeFormat.string(store.estimatedBytes)
            return store.isEstimating ? "\(size)…" : size
        }

        /// `nil` free space (unknown) never blocks a download it can't size.
        private var isOverFreeSpace: Bool {
            let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            let free = values?.volumeAvailableCapacityForImportantUsage ?? .max
            return !store.isEstimating && store.estimatedBytes > free
        }
    }

    #Preview {
        MacOfflineSelectionSheet(store: Store(initialState: OfflineSelectionFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")
        )) { OfflineSelectionFeature() } withDependencies: { $0.filesClient = .previewValue })
    }
#endif
