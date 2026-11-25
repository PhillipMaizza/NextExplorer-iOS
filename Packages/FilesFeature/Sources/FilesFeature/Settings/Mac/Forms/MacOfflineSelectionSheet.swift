#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 520
        static let listHeight: CGFloat = 280
        static let sizeColumnWidth: CGFloat = 90
        static let alreadyOfflineOpacity: Double = .opacityHalf
    }

    struct MacOfflineSelectionSheet: View {
        let store: StoreOf<OfflineSelectionFeature>
        @Dependency(\.deviceStorage) private var deviceStorage

        var body: some View {
            VStack(alignment: .leading, spacing: .space16) {
                header
                list
                if isOverFreeSpace {
                    Text(L10n.Offline.selectionInsufficientSpace)
                        .type(.body3(.regular), style: .error)
                        .macDialogReveal()
                }
                MacDialogButtons(
                    confirmTitle: L10n.Offline.selectionDownload,
                    isConfirmEnabled: store.canConfirm && !isOverFreeSpace,
                    onCancel: { store.send(.cancelTapped) },
                    onConfirm: { store.send(.confirmTapped) }
                ) {
                    estimate
                }
            }
            .padding(.space24)
            .frame(width: Metrics.width)
            .background(Color.macCard)
            .task { store.send(.onAppear) }
        }

        private var header: some View {
            HStack(alignment: .center, spacing: .space8) {
                if store.canNavigateBack {
                    Button { store.send(.backTapped) } label: { IconKit.back }
                        .buttonStyle(.macDS(.secondary, size: .small))
                        .accessibilityLabelWithTooltip(L10n.Common.back)
                }
                VStack(alignment: .leading, spacing: .space4) {
                    Text(L10n.Offline.selectionTitle).type(.headline4)
                    if !store.directoryPath.isEmpty {
                        Text(store.directoryPath)
                            .type(.body2(.regular), style: .secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            }
        }

        private var list: some View {
            VStack(spacing: .zero) {
                HStack(spacing: .space8) {
                    MacTableColumnTitle(L10n.Sort.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    MacTableColumnTitle(L10n.Sort.size)
                        .frame(width: Metrics.sizeColumnWidth, alignment: .trailing)
                }
                .padding(.horizontal, .space12)
                .padding(.vertical, .space8)
                Rectangle()
                    .fill(Color.macLine)
                    .frame(height: .borderWidthHairline)
                ScrollView {
                    LazyVStack(spacing: .zero) {
                        ForEach(store.items) { row($0) }
                    }
                    .animation(DSMotion.stateFade, value: store.directoryPath)
                }
                .frame(height: Metrics.listHeight)
                .overlay { overlay }
            }
            .macListBox()
        }

        private func row(_ item: FileItem) -> some View {
            let isOffline = store.state.isAlreadyOffline(item)
            return HStack(spacing: .space8) {
                Toggle(isOn: Binding(
                    get: { store.state.isSelected(item) || isOffline },
                    set: { _ in store.send(.selectionToggled(item)) }
                )) {
                    EmptyView()
                }
                .toggleStyle(.macCheckbox)
                .disabled(isOffline)
                .accessibilityLabel(item.name)
                MacItemIcon(name: item.name, isDirectory: item.isDirectory)
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(sizeText(item))
                    .foregroundStyle(Color.macChromeSecondary)
                    .monospacedDigit()
                    .frame(width: Metrics.sizeColumnWidth, alignment: .trailing)
                if item.isDirectory {
                    Button { store.send(.folderTapped(item)) } label: {
                        IconKit.chevronRight.foregroundStyle(Color.macChromeSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabelWithTooltip(L10n.UserDetail.directoryPickerOpen(item.name))
                }
            }
            .type(.body2(.regular))
            .foregroundStyle(Color.macChromeText)
            .opacity(isOffline ? Metrics.alreadyOfflineOpacity : 1)
            .macListRow(isSelected: false)
            .onTapGesture(count: 2) {
                if item.isDirectory {
                    store.send(.folderTapped(item))
                }
            }
            .onTapGesture {
                if !isOffline {
                    store.send(.selectionToggled(item))
                }
            }
        }

        @ViewBuilder
        private var overlay: some View {
            if store.phase == .loading, store.items.isEmpty {
                MacSpinner()
                    .macDialogReveal()
            } else if let errorMessage = store.phase.errorMessage {
                VStack(spacing: .space8) {
                    Text(errorMessage).foregroundStyle(Color.macChromeSecondary)
                    Button(L10n.Common.retry) { store.send(.retryTapped) }
                        .buttonStyle(.macDS(.secondary, size: .small))
                }
                .macDialogReveal()
            } else if store.items.isEmpty, store.phase == .loaded {
                Text(L10n.Offline.selectionEmpty)
                    .foregroundStyle(Color.macChromeSecondary)
                    .macDialogReveal()
            }
        }

        private var estimate: some View {
            HStack(spacing: .space4) {
                Text(L10n.Offline.selectionEstimate)
                    .type(.body3(.regular))
                    .foregroundStyle(Color.macChromeSecondary)
                Text(estimateText)
                    .type(.body3(.semibold))
                    .foregroundStyle(Color.macChromeText)
                    .monospacedDigit()
            }
        }

        private func sizeText(_ item: FileItem) -> String {
            if item.isDirectory {
                return store.folderSizes[item.id].map { FileSizeFormat.string($0) } ?? L10n.Common.loading
            }
            return FileSizeFormat.string(item.size)
        }

        private var estimateText: String {
            let size = FileSizeFormat.string(store.estimatedBytes)
            return store.isEstimating ? L10n.ellipsized(size) : size
        }

        private var isOverFreeSpace: Bool {
            !store.isEstimating && store.estimatedBytes > deviceStorage.freeBytes()
        }
    }

    enum PreviewOfflineItems {
        static let date = Date(timeIntervalSince1970: 1_767_225_600)
        static let items: IdentifiedArrayOf<FileItem> = [
            FileItem(name: "Albums", path: "Media", dateModified: date, size: 0, kind: FileItem.directoryKind),
            FileItem(
                name: "Podcast Episode 12.m4a",
                path: "Media",
                dateModified: date,
                size: 50_300_000,
                kind: "m4a"
            ),
            FileItem(name: "Song.mp3", path: "Media", dateModified: date, size: 7_300_000, kind: "mp3"),
            FileItem(name: "Trailer.mp4", path: "Media", dateModified: date, size: 94_400_000, kind: "mp4"),
        ]

        static var loaded: OfflineSelectionFeature.State {
            var state = OfflineSelectionFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.directoryPath = "Media"
            state.items = items
            state.phase = .loaded
            state.folderSizes = ["Media/Albums": 1_200_000_000]
            state.selection = ["Media/Song.mp3": items[2]]
            return state
        }
    }

    #Preview("Loaded") {
        MacOfflineSelectionSheet(store: Store(initialState: PreviewOfflineItems.loaded) { EmptyReducer() })
    }

    #Preview("Folder") {
        MacOfflineSelectionSheet(store: Store(initialState: OfflineSelectionFeature.State(
            serverURL: ServerSettingsPreview.serverURL
        )) { OfflineSelectionFeature() } withDependencies: { $0.filesClient = .previewValue })
    }

    #Preview("Loading") {
        MacOfflineSelectionSheet(store: Store(initialState: OfflineSelectionFeature.State(
            serverURL: ServerSettingsPreview.serverURL
        )) { EmptyReducer() })
    }
#endif
