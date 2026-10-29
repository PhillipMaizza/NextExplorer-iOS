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
            HStack(spacing: .space8) {
                Button { store.send(.backTapped) } label: { Image(systemName: "chevron.left") }
                    .disabled(!store.canNavigateBack)
                    .accessibilityLabel(L10n.Common.back)
                Text(store.directoryPath.isEmpty ? L10n.Offline.selectionTitle : store.directoryPath)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
            }
            .padding(Metrics.padding)
        }

        private var table: some View {
            Table(store.items, selection: $highlighted) {
                TableColumn("") { item in
                    let isOffline = store.state.isAlreadyOffline(item)
                    Toggle(L10n.Common.select, isOn: Binding(
                        get: { store.state.isSelected(item) || isOffline },
                        set: { _ in store.send(.selectionToggled(item)) }
                    ))
                    .labelsHidden()
                    .disabled(isOffline)
                }
                .width(Metrics.checkColumnWidth)
                TableColumn(L10n.Sort.name) { item in
                    Label {
                        Text(item.name).lineLimit(1)
                    } icon: {
                        Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                            .foregroundStyle(item.isDirectory ? Color.accentColor : .secondary)
                    }
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
                ProgressView()
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
            HStack(spacing: .space8) {
                VStack(alignment: .leading, spacing: .space2) {
                    Text(L10n.MacSettings.labelFormat(L10n.Offline.selectionEstimate) + " " + estimateText)
                        .monospacedDigit()
                    if exceedsFreeSpace {
                        Text(L10n.Offline.selectionInsufficientSpace).font(.callout).foregroundStyle(Color.negativeText)
                    }
                }
                Spacer()
                Button(L10n.Common.cancel) { store.send(.cancelTapped) }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.Offline.selectionDownload) { store.send(.confirmTapped) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!store.canConfirm || exceedsFreeSpace)
            }
            .padding(Metrics.padding)
        }

        private func sizeText(_ item: FileItem) -> String {
            if item.isDirectory {
                return store.folderSizes[item.id].map { SettingsFormat.byteFormatter.string(fromByteCount: $0) } ?? "--"
            }
            return SettingsFormat.byteFormatter.string(fromByteCount: item.size)
        }

        private var estimateText: String {
            let size = SettingsFormat.byteFormatter.string(fromByteCount: store.estimatedBytes)
            return store.isEstimating ? "\(size)…" : size
        }

        /// `nil` free space (unknown) never blocks a download it can't size.
        private var exceedsFreeSpace: Bool {
            let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            let free = values?.volumeAvailableCapacityForImportantUsage ?? .max
            return !store.isEstimating && store.estimatedBytes > free
        }
    }
#endif
