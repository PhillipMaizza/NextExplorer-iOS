#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    private enum Metrics {
        static let rowHeight: CGFloat = MacPickerMetrics.rowHeight
        static let rowInset: CGFloat = .space12
        static let tileSize: CGFloat = MacPickerMetrics.tileSize
        static let headerTop: CGFloat = .space24
        static let footerVertical: CGFloat = .space16
    }

    struct MacDestinationPickerSheet: View {
        @Bindable var store: StoreOf<DestinationPickerFeature>
        let title: String
        let confirmTitle: String

        @State private var selectedFolderID: FileItem.ID?
        @State private var selectedResultID: SearchResultItem.ID?

        private var showsItems: Bool {
            (store.purpose == .move || store.purpose == .copy) && !store.items.isEmpty
        }

        private var headerTitle: String {
            switch store.purpose {
            case .move where showsItems: L10n.Browse.destinationPickerMoveItems(store.items.count)
            case .copy where showsItems: L10n.Browse.destinationPickerCopyItems(store.items.count)
            default: title
            }
        }

        var body: some View {
            VStack(spacing: .zero) {
                header
                hairline
                HStack(spacing: .zero) {
                    if store.purpose != .replaceFile {
                        MacPickerSidebar(
                            recents: store.sidebarRecents,
                            locations: store.locations,
                            activeLocation: store.activeLocation,
                            directoryPath: store.directoryPath,
                            onRecent: { store.send(.recentTapped($0)) },
                            onLocation: { store.send(.locationTapped($0)) }
                        )
                        Rectangle().fill(Color.macLine).frame(width: .borderWidthHairline)
                    }
                    VStack(spacing: .zero) {
                        MacPickerPathBar(
                            crumbs: store.crumbs,
                            isRefining: store.isRefiningSearch,
                            onBack: { store.send(.breadcrumbTapped(path: parentPath)) },
                            onCrumb: { store.send(.breadcrumbTapped(path: $0)) }
                        )
                        hairline
                        ZStack(alignment: .top) {
                            boxContent
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .background(Color.macField)
                }
                .frame(height: MacPickerMetrics.bodyHeight)
                hairline
                footer
            }
            .frame(width: MacPickerMetrics.width)
            .animation(DSMotion.stateFade, value: store.showsSearchResults)
            .background {
                Button(L10n.Browse.open, action: openSelection)
                    .keyboardShortcut(.downArrow, modifiers: .command)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .sheet(isPresented: newFolderBinding) {
                MacPickerNewFolderSheet(store: store)
            }
            .task { store.send(.onAppear) }
            .onChange(of: selectedFolderID) { _, id in store.send(.rowSelected(id)) }
            .onChange(of: selectedResultID) { _, id in store.send(.rowSelected(id)) }
            .onChange(of: store.searchQuery) {
                selectedFolderID = nil
                selectedResultID = nil
            }
            .onChange(of: store.directoryPath) { selectedFolderID = nil }
            .onChange(of: store.selectedFilePath) { _, path in
                if let path {
                    selectedFolderID = path
                }
            }
            .onChange(of: store.selectedFolderPath) { _, path in
                if let path, !store.showsSearchResults {
                    selectedFolderID = path
                }
            }
        }

        private var hairline: some View {
            Rectangle().fill(Color.macLine).frame(height: .borderWidthHairline)
        }

        private var newFolderBinding: Binding<Bool> {
            Binding(
                get: { store.newFolder != nil },
                set: { isShown in
                    if !isShown {
                        store.send(.newFolderCancelled)
                    }
                }
            )
        }

        private var header: some View {
            HStack(spacing: .space12) {
                if showsItems {
                    MacPickerItemStack(items: store.items)
                }
                VStack(alignment: .leading, spacing: .space2) {
                    Text(headerTitle).type(.headline4).lineLimit(1)
                    if showsItems {
                        Text(store.items.map(\.name).formatted(.list(type: .and)))
                            .type(.body3(.regular), style: .secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: .space8)
                MacTextField(
                    L10n.Common.search,
                    text: $store.searchQuery.sending(\.searchQueryChanged),
                    prompt: L10n.Common.search
                )
                .frame(width: MacPickerMetrics.searchWidth)
            }
            .padding(.horizontal, .space24)
            .padding(.top, Metrics.headerTop)
            .padding(.bottom, .space16)
        }

        private var footer: some View {
            MacDialogButtons(
                confirmTitle: confirmTitle,
                isConfirmEnabled: store.canConfirm,
                onCancel: { store.send(.cancelTapped) },
                onConfirm: { store.send(.confirmTapped) }
            ) {
                if store.purpose != .replaceFile {
                    Button { store.send(.newFolderTapped) } label: {
                        Label { Text(L10n.Browse.newFolderTitle) } icon: { IconKit.macNewFolder }
                    }
                    .buttonStyle(.macDS(.secondary, size: .small))
                    .disabled(!store.canCreateFolder)
                }
                (status ?? Text(verbatim: ""))
                    .type(.body3(.regular), style: .secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentTransition(.opacity)
                    .animation(DSMotion.stateFade, value: statusKey)
            }
            .padding(.horizontal, .space24)
            .padding(.vertical, Metrics.footerVertical)
        }

        private var statusKey: String {
            "\(store.transferDestination)|\(String(describing: store.refusal))|\(store.isSearchTermTooShort)"
        }

        private var status: Text? {
            if store.isSearchTermTooShort {
                return Text(SearchHint.tooShort)
            }
            if let refusalMessage = store.refusalMessage {
                return Text(refusalMessage)
            }
            guard store.purpose != .replaceFile, store.phase == .loaded else { return nil }
            guard !store.transferDestination.isEmpty else {
                return Text(L10n.Browse.destinationPickerChooseFolder)
            }
            return Text(L10n.Browse.destinationPickerInto(store.destinationTrail))
        }

        private var parentPath: String {
            (store.directoryPath as NSString).deletingLastPathComponent
        }

        @ViewBuilder
        private var boxContent: some View {
            if store.showsSearchResults {
                if store.searchPhase == .loading, store.searchResults.isEmpty {
                    MacSpinner()
                        .frame(maxHeight: .infinity)
                        .macDialogReveal()
                } else if let errorMessage = store.searchPhase.errorMessage {
                    messageRow(errorMessage, isError: true)
                        .macDialogReveal()
                } else if store.searchResults.isEmpty {
                    messageRow(L10n.EmptyState.noSearchMatches(store.searchQuery))
                        .macDialogReveal()
                } else {
                    searchResultsList
                        .macDialogReveal()
                }
            } else if store.phase == .loading, store.folders.isEmpty {
                MacSpinner()
                    .frame(maxHeight: .infinity)
                    .macDialogReveal()
            } else if let errorMessage = store.phase.errorMessage {
                messageRow(errorMessage, isError: true) { store.send(.retryTapped) }
                    .macDialogReveal()
            } else if store.folders.isEmpty, store.files.isEmpty {
                messageRow(L10n.Browse.destinationPickerNoFolders)
                    .macDialogReveal()
            } else if store.displayedFolders.isEmpty, !store.searchQuery.isEmpty {
                messageRow(L10n.EmptyState.noSearchMatches(store.searchQuery))
                    .macDialogReveal()
            } else {
                foldersList
                    .id(store.directoryPath)
                    .macDialogReveal()
            }
        }

        private var searchResultsList: some View {
            MacPickerList(
                rows: Array(store.searchResults),
                selection: $selectedResultID,
                onOpen: { store.send(.searchResultTapped($0)) }
            ) { result in
                MacPickerRow(
                    name: result.name,
                    detail: result.path.isEmpty ? nil : PersonalSpace.trail(result.path),
                    isDirectory: result.isDirectory,
                    showsChevron: false,
                    isSelected: result.id == selectedResultID
                )
            }
        }

        private var foldersList: some View {
            MacPickerList(
                rows: Array(store.displayedFolders),
                selection: $selectedFolderID,
                onOpen: open
            ) { folder in
                MacPickerRow(
                    name: PersonalSpace.displayName(forSegment: folder.name, isFirstSegment: folder.path.isEmpty),
                    detail: nil,
                    isDirectory: folder.isDirectory,
                    showsChevron: folder.isDirectory,
                    isSelected: folder.id == selectedFolderID,
                    glyph: folder.id == PersonalSpace.rootPath ? IconKit.person : IconKit.folderFill
                )
            } footer: {
                if store.searchQuery.isEmpty {
                    ForEach(store.files) { file in
                        MacPickerRow(name: file.name, detail: nil, isDirectory: false, showsChevron: false)
                            .padding(.horizontal, Metrics.rowInset)
                            .opacity(.opacityHalf)
                            .accessibilityAddTraits(.isStaticText)
                    }
                }
            }
        }

        private func open(_ folder: FileItem) {
            if folder.isDirectory {
                store.send(.folderTapped(folder))
            } else {
                store.send(.rowSelected(folder.id))
                store.send(.confirmTapped)
            }
        }

        private func messageRow(_ message: String, isError: Bool = false, retry: (() -> Void)? = nil) -> some View {
            HStack(spacing: .space8) {
                Text(message)
                    .type(.body2(.regular), style: isError ? .error : .secondary)
                    .lineLimit(2)
                Spacer(minLength: .zero)
                if let retry {
                    Button(L10n.Common.retry, action: retry)
                        .buttonStyle(.macDS(.secondary, size: .small))
                }
            }
            .padding(.horizontal, Metrics.rowInset)
            .frame(minHeight: Metrics.rowHeight)
        }

        private func openSelection() {
            if store.showsSearchResults {
                if let id = selectedResultID, let result = store.searchResults[id: id] {
                    store.send(.searchResultTapped(result))
                }
            } else if let id = selectedFolderID, let folder = store.folders[id: id], folder.isDirectory {
                store.send(.folderTapped(folder))
            }
        }
    }

    @MainActor
    private func previewStore(_ state: DestinationPickerFeature.State) -> StoreOf<DestinationPickerFeature> {
        Store(initialState: state) { DestinationPickerFeature() } withDependencies: {
            $0.filesClient = .previewValue
        }
    }

    private let previewServer = URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")

    #Preview("Move") {
        MacDestinationPickerSheet(
            store: previewStore(DestinationPickerFeature.State(
                serverURL: previewServer,
                items: [FileItem(name: "report.pdf", path: "Documents", dateModified: Date(), size: 1_024, kind: "pdf")]
            )),
            title: L10n.Browse.destinationPickerMoveTitle,
            confirmTitle: L10n.Browse.destinationPickerConfirmMove
        )
    }

    #Preview("Short term filters by name") {
        var state = DestinationPickerFeature.State(serverURL: previewServer, uploadStartingAt: "")
        state.searchQuery = "P"
        return MacDestinationPickerSheet(
            store: previewStore(state),
            title: L10n.Uploads.destinationTitle,
            confirmTitle: L10n.Uploads.destinationConfirm
        )
    }

    #Preview("Upload") {
        MacDestinationPickerSheet(
            store: previewStore(DestinationPickerFeature.State(
                serverURL: previewServer,
                uploadStartingAt: "Documents"
            )),
            title: L10n.Uploads.destinationTitle,
            confirmTitle: L10n.Uploads.destinationConfirm
        )
    }

    #Preview("Load failed") {
        MacDestinationPickerSheet(
            store: Store(initialState: DestinationPickerFeature.State(
                serverURL: previewServer,
                uploadStartingAt: "Documents"
            )) { DestinationPickerFeature() } withDependencies: {
                $0.filesClient = .previewValue
                $0.filesClient.browse = { _, _ in throw FilesClientError.offline }
            },
            title: L10n.Browse.destinationPickerMoveTitle,
            confirmTitle: L10n.Browse.destinationPickerConfirmMove
        )
    }
#endif
