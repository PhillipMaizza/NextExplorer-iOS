#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    private enum Metrics {
        static let padding: CGFloat = .space24
        static let spacing: CGFloat = .space16
        static let searchWidth: CGFloat = 180
        static let height: CGFloat = 456
        static let minBoxHeight: CGFloat = 160
        static let rowHeight: CGFloat = .size32
        static let backRowHeight: CGFloat = .size40
        static let rowInset: CGFloat = .space12
        static let tileSize: CGFloat = 22
    }

    /// Move to, Copy to, Upload to and Restore to as a Mac sheet: recent folders in their own box,
    /// then the folder on screen with Back and its folders (double click, ⌘↓ or VoiceOver opens one),
    /// then Cancel and the confirm button for the folder on screen.
    struct MacDestinationPickerSheet: View {
        @Bindable var store: StoreOf<DestinationPickerFeature>
        let title: String
        let confirmTitle: String

        @State private var selectedFolderID: FileItem.ID?
        @State private var selectedResultID: SearchResultItem.ID?

        var body: some View {
            VStack(alignment: .leading, spacing: Metrics.spacing) {
                header
                if store.showsRecentsSection {
                    recentsBox
                        .macDialogReveal()
                }
                folderBox
                if store.isSearchTermTooShort {
                    Text(SearchHint.tooShort)
                        .type(.body3(.regular), style: .secondary)
                        .macDialogReveal()
                }
                MacDialogButtons(
                    confirmTitle: confirmTitle,
                    isConfirmEnabled: store.canConfirm,
                    onCancel: { store.send(.cancelTapped) },
                    onConfirm: { store.send(.confirmTapped) }
                )
            }
            .padding(Metrics.padding)
            .frame(width: MacFormSheetMetrics.width, height: Metrics.height)
            .animation(DSMotion.stateFade, value: store.showsRecentsSection)
            .animation(DSMotion.stateFade, value: store.showsSearchResults)
            .background {
                Button(L10n.Browse.open, action: openSelection)
                    .keyboardShortcut(.downArrow, modifiers: .command)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
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
        }

        private var header: some View {
            HStack(spacing: .space8) {
                Text(title).type(.headline4).lineLimit(1)
                Spacer(minLength: .space8)
                if store.isRefiningSearch {
                    DSSpinner(size: .small)
                        .macDialogReveal()
                }
                MacTextField(
                    L10n.Common.search,
                    text: $store.searchQuery.sending(\.searchQueryChanged),
                    prompt: L10n.Common.search
                )
                .frame(width: Metrics.searchWidth)
            }
        }

        private var recentsBox: some View {
            VStack(alignment: .leading, spacing: .zero) {
                Text(L10n.Browse.destinationPickerRecent)
                    .type(.caption(.semibold), style: .secondary)
                    .padding(.horizontal, Metrics.rowInset)
                    .padding(.top, .space8)
                    .padding(.bottom, .space2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(store.displayedRecents, id: \.self) { path in
                    Button { store.send(.recentTapped(path)) } label: {
                        MacPickerRow(
                            name: PersonalSpace.folderTitle(path),
                            detail: PersonalSpace.trail((path as NSString).deletingLastPathComponent),
                            isDirectory: true,
                            showsChevron: false
                        )
                        .padding(.horizontal, Metrics.rowInset)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, .space4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .macListBox()
        }

        private var folderBox: some View {
            VStack(spacing: .zero) {
                if !store.showsSearchResults {
                    backRow
                        .macDialogReveal()
                }
                ZStack(alignment: .top) {
                    boxContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(minHeight: Metrics.minBoxHeight, maxHeight: .infinity)
            .macListBox()
        }

        private var backRow: some View {
            HStack(spacing: .zero) {
                if store.directoryPath.isEmpty {
                    folderTitle
                } else {
                    Button { store.send(.breadcrumbTapped(path: parentPath)) } label: {
                        HStack(spacing: .space4) {
                            IconKit.back
                                .imageScale(.small)
                                .foregroundStyle(Color.macChromeSecondary)
                            folderTitle
                        }
                        .padding(.leading, .space8)
                        .padding(.trailing, .space12)
                        .padding(.vertical, .space4)
                        .background(Capsule().fill(Color.macSegment))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabelWithTooltip(L10n.Common.back)
                }
                Spacer(minLength: .zero)
            }
            .foregroundStyle(Color.macChromeText)
            .padding(.horizontal, .space8)
            .frame(height: Metrics.backRowHeight)
        }

        private var folderTitle: some View {
            Text(PersonalSpace.folderTitle(store.directoryPath))
                .type(.body2(.bold))
                .lineLimit(1)
                .truncationMode(.middle)
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
            } else if store.folders.isEmpty {
                messageRow(L10n.Browse.destinationPickerNoFolders)
                    .macDialogReveal()
            } else if store.displayedFolders.isEmpty {
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

    private struct MacPickerRow: View {
        let name: String
        let detail: String?
        let isDirectory: Bool
        let showsChevron: Bool
        var isSelected = false
        var glyph = IconKit.folderFill

        var body: some View {
            HStack(spacing: .space8) {
                if isDirectory {
                    MacFolderTile(size: Metrics.tileSize, glyph: glyph)
                        .environment(\.backgroundProminence, isSelected ? .increased : .standard)
                } else {
                    IconKit.document
                        .foregroundStyle(Color.macChromeSecondary)
                        .frame(width: Metrics.tileSize)
                        .accessibilityHidden(true)
                }
                Text(name)
                    .type(.body2(.regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: .space8)
                if let detail {
                    Text(detail)
                        .type(.body3(.regular), style: .secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                if showsChevron {
                    IconKit.chevronRight
                        .imageScale(.small)
                        .foregroundStyle(Color.macChromeSecondary)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Color.macChromeText)
            .frame(minHeight: Metrics.rowHeight)
            .accessibilityElement(children: .combine)
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
            title: "Move to…",
            confirmTitle: "Move Here"
        )
    }

    #Preview("Short term filters by name") {
        var state = DestinationPickerFeature.State(serverURL: previewServer, uploadStartingAt: "")
        state.searchQuery = "P"
        return MacDestinationPickerSheet(store: previewStore(state), title: "Upload to…", confirmTitle: "Upload here")
    }

    #Preview("Upload") {
        MacDestinationPickerSheet(
            store: previewStore(DestinationPickerFeature.State(
                serverURL: previewServer,
                uploadStartingAt: "Documents"
            )),
            title: "Upload to…",
            confirmTitle: "Upload here"
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
            title: "Move to…",
            confirmTitle: "Move Here"
        )
    }
#endif
