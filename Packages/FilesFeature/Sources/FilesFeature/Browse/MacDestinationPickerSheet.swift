#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 540
        static let height: CGFloat = 460
        static let padding: CGFloat = .space16
        static let searchWidth: CGFloat = 180
    }

    /// Move to and Upload to as a native Mac dialog: the folder being looked at with Back and a
    /// search field, its folders in a list (double click to open one), then Cancel and the
    /// confirm button for the folder on screen.
    struct MacDestinationPickerSheet: View {
        @Bindable var store: StoreOf<DestinationPickerFeature>
        let title: String
        let confirmTitle: String

        var body: some View {
            VStack(spacing: 0) {
                header
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                MacDialogButtons(
                    confirmTitle: confirmTitle,
                    isConfirmEnabled: store.canConfirm,
                    onCancel: { store.send(.cancelTapped) },
                    onConfirm: { store.send(.confirmTapped) }
                )
                .padding(Metrics.padding)
            }
            .frame(width: Metrics.width, height: Metrics.height)
            .task { store.send(.onAppear) }
        }

        private var header: some View {
            MacSheetHeader(
                title: title,
                subtitle: store.directoryPath,
                canGoBack: store.canNavigateBack,
                onBack: { store.send(.backTapped) }
            ) {
                TextField(L10n.Common.search, text: $store.searchQuery.sending(\.searchQueryChanged), prompt: Text(L10n.Common.search))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Metrics.searchWidth)
            }
            .padding(Metrics.padding)
        }

        @ViewBuilder
        private var content: some View {
            if !store.searchQuery.isEmpty {
                if store.isSearching, store.searchResults?.isEmpty ?? true {
                    ProgressView().controlSize(.small)
                } else if let results = store.searchResults, results.isEmpty {
                    ContentUnavailableView.search(text: store.searchQuery)
                } else {
                    List(store.searchResults ?? []) { result in
                        MacItemLabel(name: result.name, subtitle: result.path.isEmpty ? nil : result.path, isDirectory: true)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { store.send(.searchResultTapped(result)) }
                    }
                }
            } else if store.phase == .loading, store.folders.isEmpty {
                ProgressView().controlSize(.small)
            } else if let errorMessage = store.phase.errorMessage {
                EmptyStateView(icon: IconKit.warning, message: errorMessage) { store.send(.retryTapped) }
            } else if store.folders.isEmpty {
                EmptyStateView(icon: IconKit.folder, message: L10n.Browse.destinationPickerNoFolders)
            } else {
                List(store.folders) { folder in
                    MacItemLabel(name: folder.name, isDirectory: true)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { store.send(.folderTapped(folder)) }
                }
            }
        }
    }

    #Preview("Move") {
        MacDestinationPickerSheet(
            store: Store(initialState: DestinationPickerFeature.State(
                serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
                items: [FileItem(name: "report.pdf", path: "Documents", dateModified: Date(), size: 1_024, kind: "pdf")]
            )) { DestinationPickerFeature() } withDependencies: { $0.filesClient = .previewValue },
            title: "Move “report.pdf”",
            confirmTitle: "Move"
        )
    }

    #Preview("Upload") {
        MacDestinationPickerSheet(
            store: Store(initialState: DestinationPickerFeature.State(
                serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
                uploadStartingAt: "Documents"
            )) { DestinationPickerFeature() } withDependencies: { $0.filesClient = .previewValue },
            title: "Upload To",
            confirmTitle: "Choose"
        )
    }
#endif
