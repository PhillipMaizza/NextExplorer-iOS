import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import PhotosUI
import SwiftUI

private enum BrowseViewMode: String {
    case list, grid
}

private enum Constants {
    static let emptyStateSpacing: CGFloat = .space8
    static let emptyStateIconSize: CGFloat = .superIcon
    static let gridSpacing: CGFloat = .space16
    /// Inset between a grid tile's content and its `backgroundSecondary` card edge.
    static let gridCellPadding: CGFloat = .space12
    static let listDiffSpringResponse: Double = 0.35
    static let listDiffSpringDamping: Double = 0.8
    static let overlayCrossfadeDuration: Double = 0.2
    /// Skeleton to loaded content crossfade — a touch longer than the overlay swap so the
    /// placeholder visibly resolves into the real rows rather than blinking out.
    static let contentRevealDuration: Double = 0.3
    /// One size for every glyph in the multi-select bottom toolbar — SF Symbols have
    /// different intrinsic aspect ratios, so without an explicit frame `trash` and `star`
    /// render visibly different heights.
    static let selectionToolbarIconSize: CGFloat = .iconMedium
    /// Height of the invisible long-press paste target past the last row.
    static let pasteTargetMinHeight: CGFloat = 260
    /// The upload `+` is the folder's primary action, so it carries the accent tint and a
    /// heavier glyph than the neutral options menu beside it.
    static let uploadButtonWeight: Font.Weight = .bold
    /// Gap between the empty folder message and its upload call to action.
    static let emptyUploadButtonTopSpacing: CGFloat = .space24
    static let emptyUploadButtonHeight: CGFloat = .size48
    static let emptyUploadButtonHPadding: CGFloat = .space24
}

/// The list body shown at every depth of Browse: root and every pushed subfolder
/// render this same view, scoped to their own `BrowseFeature` store. The list/grid
/// choice is a per-device display preference, not per-folder state, so it's stored
/// directly here rather than threaded through `BrowseFeature.State`.
struct BrowseContentView: View {
    @Bindable var store: StoreOf<BrowseFeature>
    @AppStorage(AppStorageKeys.browseViewMode) private var viewModeRaw = BrowseViewMode.list.rawValue
    @AppStorage(AppStorageKeys.thumbnailSize) private var thumbnailSizeRaw = ThumbnailSize.medium.rawValue
    @AppStorage(AppStorageKeys.removeArchiveAfterDownload) private var removeArchiveAfterDownload = false
    @AppStorage(AppStorageKeys.keepClipboardAfterCopy) private var keepClipboardAfterCopy = false
    @State private var isSortSheetPresented = false
    @State private var toastMessage: DSToastMessage?
    /// The item whose "Create Share Link" sheet is open (from the context menu or the
    /// selection toolbar). Local view state, not routed through `BrowseFeature` — the sheet
    /// owns its own ad-hoc `CreateShareLinkFeature` store.
    @State private var shareTarget: FileItem?
    /// Flipped once a pull-to-refresh completes, purely as a `.hapticFeedback` trigger — the
    /// value itself is meaningless, only the fact that it just changed matters.
    @State private var didFinishRefreshing = false
    @State private var isFilesPickerPresented = false
    @State private var isPhotosPickerPresented = false
    @State private var isCameraPresented = false
    @State private var isCameraDeniedAlertPresented = false
    @State private var photosSelection: [PhotosPickerItem] = []
    @Shared(.inMemory(UploadBarChrome.visibilityKey)) private var isUploadBarVisible = false
    @Shared(.inMemory(UploadBarChrome.heightKey)) private var uploadBarHeight = UploadBarChrome.fallbackHeight

    private var viewMode: BrowseViewMode {
        BrowseViewMode(rawValue: viewModeRaw) ?? .list
    }

    private var thumbnailSize: ThumbnailSize {
        ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize.gridItemMinWidth), spacing: Constants.gridSpacing)]
    }

    /// Pre-filters kinds `rowTapped` would just silently no-op on (or, for unsupported video
    /// containers, previously opened a full-screen "can't play this" view for) — a toast reads
    /// better than either a dead tap or interrupting with a whole screen.
    private func handleTap(_ item: FileItem) {
        guard !item.isDirectory else {
            store.send(.rowTapped(item))
            return
        }
        guard !item.isUnsupportedForPreview else {
            toastMessage = DSToastMessage(icon: IconKit.warning, text: L10n.Browse.unsupportedFileType)
            return
        }
        store.send(.rowTapped(item))
    }

    /// Search results only report `dir`/`file` for kind, so derive a real extension from the
    /// file name for the row icon — the same thing `searchResultTapped` hands the preview.
    private func searchResultKind(_ result: SearchResultItem) -> String {
        result.isDirectory ? result.kind : (result.name as NSString).pathExtension.lowercased()
    }

    var body: some View {
        browsingContent
            .sheet(item: $store.scope(state: \.destinationPicker, action: \.destinationPicker)) { pickerStore in
                DestinationPickerView(store: pickerStore)
            }
            .sheet(item: $store.scope(state: \.uploadReview, action: \.uploadReview)) { reviewStore in
                UploadReviewView(store: reviewStore)
            }
            .sheet(item: infoPhaseBinding) { phase in
                infoSheetContent(for: phase)
            }
            .sheet(item: $store.scope(state: \.permissions, action: \.permissions)) { permissionsStore in
                PermissionsSheet(store: permissionsStore)
            }
            .fullScreenCover(item: previewItemBinding) { item in
                previewContent(for: item)
            }
            .sheet(item: $shareTarget) { item in
                CreateShareLinkSheet(
                    store: Store(
                        initialState: CreateShareLinkFeature.State(
                            serverURL: store.serverURL,
                            itemName: item.name,
                            itemPath: item.path,
                            isDirectory: item.isDirectory
                        )
                    ) {
                        CreateShareLinkFeature()
                    }
                )
            }
            .dsToast($toastMessage, extraBottomInset: bottomChromeClearance)
            .dsToast(progressToastBinding, extraBottomInset: bottomChromeClearance)
            // `fileActionErrorMessage` (rename/delete/extract/compress failures) was set on
            // `State` but never actually read by any view — silently swallowed. Mirrored into
            // the same toast the unsupported-file-type warning uses.
            .onChange(of: store.fileActionErrorMessage) { _, newValue in
                guard let newValue else { return }
                toastMessage = DSToastMessage(icon: IconKit.warning, text: newValue)
            }
            .onChange(of: store.downloadSuccessMessage) { _, newValue in
                guard let newValue else { return }
                toastMessage = .success(newValue, actionTitle: L10n.Browse.open) {
                    store.send(.delegate(.openDownloadsTapped))
                }
            }
            .onChange(of: store.transferSuccessMessage) { _, newValue in
                guard let newValue else { return }
                toastMessage = .success(newValue)
            }
            .onChange(of: store.clipboardStagedMessage) { _, newValue in
                guard let newValue else { return }
                toastMessage = .success(newValue)
            }
            .onChange(of: store.transferErrorMessage) { _, newValue in
                guard let newValue else { return }
                toastMessage = .failure(newValue, actionTitle: L10n.Common.retry) {
                    store.send(.retryTransferTapped, animation: .default)
                }
            }
            .task {
                store.send(.onAppear)
            }
    }

    /// Split out of `body`: with every modifier below chained directly onto the file-action
    /// sheets/covers added above, the compiler couldn't type-check the whole expression in
    /// reasonable time.
    private var browsingContent: some View {
        Group {
            if isInitialLoad {
                BrowseSkeletonView(
                    isGridView: viewMode == .grid,
                    gridColumns: gridColumns,
                    iconSize: thumbnailSize.iconSize
                )
                .transition(.opacity)
            } else if viewMode == .list {
                listContent
                    .transition(.opacity)
            } else {
                gridContent
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: Constants.contentRevealDuration), value: isInitialLoad)
        .tint(Color.accent)
        .searchable(
            text: $store.searchQuery.sending(\.searchQueryChanged),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: L10n.Common.search
        )
        .searchScopes($store.searchScope.sending(\.searchScopeChanged)) {
            ForEach(BrowseFeature.SearchScope.allCases, id: \.self) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .refreshable {
            await store.send(.refreshButtonTapped).finish()
            didFinishRefreshing.toggle()
        }
        .hapticFeedback(.success, trigger: didFinishRefreshing) { _, _ in store.errorMessage == nil }
        .hapticFeedback(.error, trigger: store.errorMessage) { _, newValue in newValue != nil }
        .overlay {
            overlayStateContent
                .id(overlayState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: Constants.overlayCrossfadeDuration), value: overlayState)
        .toolbar {
            selectSortToolbar(
                isSelecting: store.isSelecting,
                isAllSelected: isAllSelected,
                isSelectAvailable: !store.isSearching && !store.displayedItems.isEmpty,
                isGridView: viewMode == .grid,
                onSelectModeToggled: { store.send(.selectModeToggled) },
                onSelectAllToggled: { store.send(isAllSelected ? .deselectAllTapped : .selectAllTapped) },
                onCancel: { store.send(.selectModeToggled) },
                onToggleViewMode: {
                    withAnimation {
                        viewModeRaw = (viewMode == .list ? BrowseViewMode.grid : .list).rawValue
                    }
                },
                clipboardMenu: {
                    if store.clipboard != nil && !store.directoryPath.isEmpty {
                        Section {
                            Button {
                                store.send(.pasteTapped(keepItemsAfterCopy: keepClipboardAfterCopy), animation: .default)
                            } label: {
                                Label { Text(pasteActionTitle) } icon: { IconKit.paste }
                            }
                            .disabled(!canPasteIntoCurrentFolder)
                            Button {
                                store.send(.clipboardCleared, animation: .default)
                            } label: {
                                Label { Text(L10n.Browse.actionClearClipboard) } icon: { IconKit.close }
                            }
                        }
                    }
                }
            ) {
                Button {
                    isSortSheetPresented = true
                } label: {
                    Label { Text(L10n.Common.sort) } icon: { IconKit.sort }
                }
            }
            if !store.isSelecting && canUploadHere {
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    UploadSourceMenu(
                        label: {
                            IconKit.plus
                                .fontWeight(Constants.uploadButtonWeight)
                                .foregroundStyle(Color.accent)
                        },
                        leadingActions: {
                            if !store.directoryPath.isEmpty {
                                Button { store.send(.newFolderTapped) } label: {
                                    Label { Text(L10n.Browse.actionNewFolder) } icon: { IconKit.folder }
                                }
                            }
                        },
                        isFilesPickerPresented: $isFilesPickerPresented,
                        isPhotosPickerPresented: $isPhotosPickerPresented,
                        isCameraPresented: $isCameraPresented,
                        isCameraDeniedAlertPresented: $isCameraDeniedAlertPresented
                    )
                    .accessibilityLabel(L10n.Uploads.menuTitle)
                }
            }
        }
        .modifier(UploadPickers(
            isFilesPickerPresented: $isFilesPickerPresented,
            isPhotosPickerPresented: $isPhotosPickerPresented,
            isCameraPresented: $isCameraPresented,
            isCameraDeniedAlertPresented: $isCameraDeniedAlertPresented,
            photosSelection: $photosSelection,
            onDocumentsPicked: { urls in
                guard !urls.isEmpty else { return }
                store.send(.beginUpload(.documents(urls)))
            },
            onPhotosPicked: { items in
                guard !items.isEmpty else { return }
                store.send(.beginUpload(.photos(items)))
                photosSelection = []
            },
            onCameraCaptured: { url in
                store.send(.beginUpload(.camera(url)))
            }
        ))
        .hapticFeedback(.selection, trigger: viewModeRaw)
        .hapticFeedback(.selection, trigger: store.isSelecting)
        .toolbar(store.isSelecting ? .hidden : .automatic, for: .tabBar)
        .toolbar {
            if store.isSelecting {
                ToolbarItem(placement: .bottomBar) {
                    Spacer()
                }
                if let singleSelectedItem, store.access?.canWrite ?? false {
                    ToolbarItem(placement: .bottomBar) {
                        selectionToolbarButton(icon: IconKit.rename) {
                            store.send(.renameTapped(singleSelectedItem))
                        }
                    }
                }
                if let singleSelectedItem, store.access?.canShare ?? false {
                    ToolbarItem(placement: .bottomBar) {
                        selectionToolbarButton(icon: IconKit.shareLink) {
                            shareTarget = singleSelectedItem
                        }
                    }
                }
                if isFavoriteActionVisible {
                    ToolbarItem(placement: .bottomBar) {
                        selectionToolbarButton(icon: isEntireSelectionAlreadyFavorited ? IconKit.starFill : IconKit.star) {
                            store.send(.bulkFavoriteTapped)
                        }
                    }
                }
                if isTransferActionVisible {
                    ToolbarItem(placement: .bottomBar) {
                        selectionToolbarButton(icon: IconKit.copy) {
                            store.send(.bulkCopyTapped, animation: .default)
                        }
                    }
                }
                if isTransferActionVisible && (store.access?.canWrite ?? false) && (store.access?.canDelete ?? false) {
                    ToolbarItem(placement: .bottomBar) {
                        selectionToolbarButton(icon: IconKit.move) {
                            store.send(.bulkMoveTapped, animation: .default)
                        }
                    }
                }
                if isDownloadActionVisible {
                    ToolbarItem(placement: .bottomBar) {
                        selectionToolbarButton(icon: IconKit.download) {
                            store.send(.bulkDownloadTapped(.documents, removeArchiveAfterDownload: removeArchiveAfterDownload))
                        }
                    }
                }
                if isDeleteActionVisible {
                    ToolbarItem(placement: .bottomBar) {
                        selectionToolbarButton(icon: IconKit.delete, role: .destructive, tint: .negative) {
                            store.send(.bulkDeleteTapped)
                        }
                    }
                }
            }
        }
        .animation(
            .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
            value: store.selectedItemIDs
        )
        .sheet(isPresented: bulkDeleteConfirmationBinding) {
            DSAlertSheet(
                icon: IconKit.delete,
                title: bulkDeleteConfirmationTitle,
                message: deleteConfirmationMessage,
                confirmTitle: L10n.Common.delete,
                dismissTitle: L10n.Common.cancel,
                role: .destructive,
                closeAccessibilityLabel: L10n.Common.close,
                onConfirm: { store.send(.bulkDeleteConfirmed) },
                onDismiss: { store.send(.bulkDeleteCancelled) }
            )
        }
        .hapticFeedback(.warning, trigger: store.bulkDeleteConfirmationIsPresented)
        .sheet(isPresented: $isSortSheetPresented) {
            SortSheet(
                options: BrowseFeature.SortOption.allCases,
                directions: BrowseFeature.SortDirection.allCases,
                sortOption: store.sortOption,
                sortDirection: store.sortDirection,
                optionIcon: { $0.icon },
                optionTitle: { $0.title },
                directionIcon: { $0.icon },
                directionTitle: { $0.title },
                onSelectOption: { store.send(.sortOptionChanged($0)) },
                onSelectDirection: { store.send(.sortDirectionChanged($0)) },
                onDismiss: { isSortSheetPresented = false }
            )
        }
        .sheet(item: renameItemBinding) { item in
            NameInputSheet(
                icon: IconKit.rename,
                title: L10n.Browse.renameTitle,
                placeholder: L10n.Browse.renameNamePlaceholder,
                confirmTitle: L10n.Common.save,
                initialName: item.name,
                isBusy: store.isPerformingFileAction,
                onConfirm: { store.send(.renameConfirmed($0)) },
                onCancel: { store.send(.renameCancelled) }
            )
        }
        .sheet(isPresented: newFolderSheetBinding) {
            NameInputSheet(
                icon: IconKit.folder,
                title: L10n.Browse.newFolderTitle,
                placeholder: L10n.Browse.newFolderPlaceholder,
                confirmTitle: L10n.Browse.newFolderConfirm,
                isBusy: store.isPerformingFileAction,
                onConfirm: { store.send(.newFolderConfirmed($0)) },
                onCancel: { store.send(.newFolderCancelled) }
            )
        }
        .sheet(isPresented: isDeletingBinding) {
            DSAlertSheet(
                icon: IconKit.delete,
                title: deleteConfirmationTitle,
                message: deleteConfirmationMessage,
                confirmTitle: L10n.Common.delete,
                dismissTitle: L10n.Common.cancel,
                role: .destructive,
                closeAccessibilityLabel: L10n.Common.close,
                onConfirm: { store.send(.deleteConfirmed) },
                onDismiss: { store.send(.deleteCancelled) }
            )
        }
        .hapticFeedback(.warning, trigger: store.deleteConfirmationItem)
        .sheet(isPresented: transferConflictBinding) {
            DSAlertSheet(
                icon: IconKit.warning,
                title: L10n.Browse.transferConflictTitle,
                message: transferConflictMessage,
                confirmTitle: L10n.Browse.transferConflictReplace,
                dismissTitle: L10n.Common.cancel,
                neutralTitle: L10n.Browse.transferConflictKeepBoth,
                role: .destructive,
                closeAccessibilityLabel: L10n.Common.close,
                onConfirm: { store.send(.transferConflictResolved(.replace), animation: .default) },
                onNeutral: { store.send(.transferConflictResolved(.keepBoth), animation: .default) },
                onDismiss: { store.send(.transferConflictResolved(nil)) }
            )
        }
        .hapticFeedback(.warning, trigger: store.transferConflict)
    }

    private var previewItemBinding: Binding<FileItem?> {
        Binding(
            get: { store.previewItem },
            set: { if $0 == nil { store.send(.previewDismissed) } }
        )
    }

    /// Read-only from the store's perspective: `fileActionProgressMessage` clears itself once
    /// the extract/compress effect resolves, so there's nothing for the view to write back —
    /// the toast has no auto-dismiss timer to fire early either (`DSToastMessage.progress`
    /// sets `isPersistent`), so the setter is genuinely never called in practice.
    private var progressToastBinding: Binding<DSToastMessage?> {
        Binding(
            get: { store.fileActionProgressMessage.map { DSToastMessage.progress($0) } },
            set: { _ in }
        )
    }

    @ViewBuilder
    private func previewContent(for item: FileItem) -> some View {
        if item.isStreamableMedia, let url = FilesClient.previewURL(serverURL: store.serverURL, item: item) {
            // Guaranteed `isNativelyPlayable` by this point — unsupported containers/codecs
            // are caught by the toast in `handleTap`, before `rowTapped` is ever sent.
            StreamingPreviewView(
                item: item,
                url: url,
                serverURL: store.serverURL,
                onDismiss: { store.send(.previewDismissed) },
                onShare: (store.access?.canShare ?? false) ? {
                    store.send(.previewDismissed)
                    shareTarget = item
                } : nil,
                onRename: (store.access?.canWrite ?? false) ? {
                    store.send(.previewDismissed)
                    store.send(.renameTapped(item))
                } : nil,
                onDownload: (store.access?.canDownload ?? false) ? {
                    store.send(.previewDismissed)
                    store.send(.downloadTapped(item, .documents, removeArchiveAfterDownload: removeArchiveAfterDownload))
                } : nil,
                onDelete: (store.access?.canDelete ?? false) ? {
                    store.send(.previewDismissed)
                    store.send(.deleteTapped(item))
                } : nil
            )
        } else if item.isBrowsableArchive {
            ArchiveBrowserView(item: item, serverURL: store.serverURL, onDismiss: { store.send(.previewDismissed) })
        } else if (item.isImage || item.isRawImage) && !item.isSVG {
            ImageGalleryView(
                items: store.displayedItems.filter { ($0.isImage || $0.isRawImage) && !$0.isSVG },
                initialItem: item,
                serverURL: store.serverURL,
                onDismiss: { store.send(.previewDismissed) },
                onShare: (store.access?.canShare ?? false) ? { current in
                    store.send(.previewDismissed)
                    shareTarget = current
                } : nil,
                onRename: (store.access?.canWrite ?? false) ? { current in
                    store.send(.previewDismissed)
                    store.send(.renameTapped(current))
                } : nil,
                onDownload: (store.access?.canDownload ?? false) ? { current in
                    store.send(.previewDismissed)
                    store.send(.downloadTapped(current, .documents, removeArchiveAfterDownload: removeArchiveAfterDownload))
                } : nil,
                onDelete: (store.access?.canDelete ?? false) ? { current in
                    store.send(.previewDismissed)
                    store.send(.deleteTapped(current))
                } : nil
            )
        } else if item.isPreviewableViaDownload {
            FilePreviewContainerView(
                fileURL: store.previewFileURL,
                errorMessage: store.previewErrorMessage,
                onDismiss: { store.send(.previewDismissed) },
                onShareLink: (store.access?.canShare ?? false) ? {
                    store.send(.previewDismissed)
                    shareTarget = item
                } : nil,
                onRename: (store.access?.canWrite ?? false) ? {
                    store.send(.previewDismissed)
                    store.send(.renameTapped(item))
                } : nil,
                onDownload: (store.access?.canDownload ?? false) ? {
                    store.send(.previewDismissed)
                    store.send(.downloadTapped(item, .documents, removeArchiveAfterDownload: removeArchiveAfterDownload))
                } : nil,
                onDelete: (store.access?.canDelete ?? false) ? {
                    store.send(.previewDismissed)
                    store.send(.deleteTapped(item))
                } : nil
            )
        } else {
            TextFilePreviewView(
                item: item,
                serverURL: store.serverURL,
                fileName: item.name,
                kind: item.kind,
                content: store.textContent,
                errorMessage: store.textEditorErrorMessage,
                isLoading: store.isLoadingTextContent,
                isSaving: store.isSavingTextContent,
                onSave: { store.send(.textSaveTapped($0)) },
                onDismiss: { store.send(.previewDismissed) }
            )
        }
    }

    /// Distinct identities for "still loading" vs. "have a result", so swapping between the
    /// two (once the fetch resolves) is a genuinely fresh sheet presentation rather than an
    /// in-place content change — see `FileInfoLoadingSheet`'s doc comment for why that
    /// matters for getting the right height.
    private enum InfoSheetPhase: Identifiable, Equatable {
        case loading(FileItem)
        case result(FileItem)

        var id: String {
            switch self {
            case let .loading(item): "loading-\(item.id)"
            case let .result(item): "result-\(item.id)"
            }
        }
    }

    private var infoPhase: InfoSheetPhase? {
        guard let item = store.infoItem else { return nil }
        guard store.infoMetadata != nil || store.infoErrorMessage != nil else {
            return .loading(item)
        }
        return .result(item)
    }

    private var infoPhaseBinding: Binding<InfoSheetPhase?> {
        Binding(
            get: { infoPhase },
            set: { if $0 == nil { store.send(.infoDismissed) } }
        )
    }

    @ViewBuilder
    private func infoSheetContent(for phase: InfoSheetPhase) -> some View {
        switch phase {
        case let .loading(item):
            FileInfoLoadingSheet(item: item, onDismiss: { store.send(.infoDismissed) })
        case let .result(item):
            FileInfoSheet(
                item: item,
                metadata: store.infoMetadata,
                usage: store.infoUsage,
                errorMessage: store.infoErrorMessage,
                onDismiss: { store.send(.infoDismissed) }
            )
        }
    }

    /// Drives the rename `NameInputSheet`; a swipe down dismiss routes back through the reducer
    /// so `renameSheetItem` clears. The reducer also nils it itself on a completed rename.
    private var renameItemBinding: Binding<FileItem?> {
        Binding(
            get: { store.renameSheetItem },
            set: { if $0 == nil { store.send(.renameCancelled) } }
        )
    }

    private var newFolderSheetBinding: Binding<Bool> {
        Binding(
            get: { store.isNewFolderSheetPresented },
            set: { if !$0 { store.send(.newFolderCancelled) } }
        )
    }

    // No op setter: the sheet is dismiss disabled and only closes through one of
    // `DSAlertSheet`'s own buttons, which drive the reducer directly.
    private var isDeletingBinding: Binding<Bool> {
        Binding(get: { store.deleteConfirmationItem != nil }, set: { _ in })
    }

    private var deleteConfirmationTitle: String {
        guard let item = store.deleteConfirmationItem else { return L10n.Browse.deleteConfirmTitle }
        return L10n.Browse.deleteConfirmOne(item.name)
    }

    /// `deleteMessage` plus, once `delete-impact` answers, a line about the share links the
    /// delete would break. Shared by the single- and bulk-delete alerts since only one is
    /// ever up. A still-running or failed check adds nothing / a soft note respectively.
    private var deleteConfirmationMessage: String {
        let base = L10n.Browse.deleteMessage
        switch store.deleteImpactCheck {
        case let .loaded(impact) where impact.shareCount == 1:
            return base + "\n\n" + L10n.Browse.deleteLinkedSharesOne
        case let .loaded(impact) where impact.shareCount > 1:
            return base + "\n\n" + L10n.Browse.deleteLinkedSharesMany(impact.shareCount)
        case .unavailable:
            return base + "\n\n" + L10n.Browse.deleteLinkedSharesUnavailable
        case .idle, .checking, .loaded:
            return base
        }
    }

    /// The button closures own dismissal (they clear `transferConflict`); the no op setter
    /// keeps a SwiftUI initiated dismiss from firing a second resolve into a torn down sheet.
    private var transferConflictBinding: Binding<Bool> {
        Binding(get: { store.transferConflict != nil }, set: { _ in })
    }

    private var transferConflictMessage: String {
        guard let conflict = store.transferConflict else { return "" }
        return conflict.count == 1
            ? L10n.Browse.transferConflictMessageOne(conflict.firstName)
            : L10n.Browse.transferConflictMessageMany(conflict.count)
    }

    private var isAllSelected: Bool {
        !store.displayedItems.isEmpty && store.selectedItemIDs.count == store.displayedItems.count
    }

    /// Rename only makes sense for a single target — `nil` (hiding the toolbar icon) for
    /// zero or multiple selected items.
    private var singleSelectedItem: FileItem? {
        guard store.selectedItemIDs.count == 1, let id = store.selectedItemIDs.first else { return nil }
        return store.items[id: id]
    }

    /// Only directories can be favorited, so a selection mixing a file in with a folder has
    /// no well-defined bulk target — the icon disappears entirely rather than silently
    /// ignoring the file, which a merely-disabled icon would leave ambiguous.
    private var isFavoriteActionVisible: Bool {
        !store.selectedItemIDs.isEmpty && store.selectedItemIDs.allSatisfy { id in
            store.items[id: id]?.isDirectory ?? false
        }
    }

    /// Filled when tapping the toolbar star would unfavorite the whole selection, matching
    /// the single-item context-menu icon's own filled/outline convention.
    private var isEntireSelectionAlreadyFavorited: Bool {
        !store.selectedItemIDs.isEmpty && store.selectedItemIDs.allSatisfy(store.favoritePaths.contains)
    }

    private var isDownloadActionVisible: Bool {
        !store.selectedItemIDs.isEmpty && (store.access?.canDownload ?? false)
    }

    private var isDeleteActionVisible: Bool {
        !store.selectedItemIDs.isEmpty && (store.access?.canDelete ?? false)
    }

    /// Copy/Move from the selection toolbar — available whenever anything is selected, except
    /// for a lone root location (same rule the single-item context menu enforces via
    /// `isSoleRootLocation`). Copy needs no permission; the Move button adds a
    /// `canWrite && canDelete` gate at its site.
    private var isTransferActionVisible: Bool {
        !store.selectedItemIDs.isEmpty && !(store.directoryPath.isEmpty && store.items.count <= 1)
    }

    /// A multi-select bottom-toolbar button, every glyph pinned to the same square so the
    /// row reads as uniform regardless of each symbol's intrinsic aspect ratio. Defaults to
    /// `primaryDS`; only Delete passes an explicit `.negative` tint.
    private func selectionToolbarButton(
        icon: Image,
        role: ButtonRole? = nil,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: Constants.selectionToolbarIconSize, height: Constants.selectionToolbarIconSize)
                .foregroundStyle(tint ?? Color.primaryDS)
        }
        .buttonStyle(DSHapticButtonStyle())
        .transition(.scale.combined(with: .opacity))
    }

    private var bulkDeleteConfirmationBinding: Binding<Bool> {
        Binding(get: { store.bulkDeleteConfirmationIsPresented }, set: { _ in })
    }

    private var bulkDeleteConfirmationTitle: String {
        L10n.Browse.deleteConfirmMany(store.selectedItemIDs.count)
    }

    @ViewBuilder
    private func fileActionsContextMenu(for item: FileItem) -> some View {
        // Explicit `.tint`: this whole view is under `.tint(Color.accent)`, which would
        // otherwise cascade into the menu and color every icon/label gold instead of the
        // system's normal label color — only Delete should stand out, in red.
        Button {
            store.send(.infoTapped(item))
        } label: {
            Label { Text(L10n.Browse.actionGetInfo) } icon: { IconKit.info }
        }
        .tint(.primaryDS)
        Button {
            store.send(.permissionsTapped(item))
        } label: {
            Label { Text(L10n.Browse.actionPermissions) } icon: { IconKit.lock }
        }
        .tint(.primaryDS)
        if item.isHTML {
            Button {
                store.send(.openInBrowserTapped(item))
            } label: {
                Label { Text(L10n.Browse.actionOpenInBrowser) } icon: { IconKit.web }
            }
            .tint(.primaryDS)
        }
        if store.access?.canWrite ?? false {
            Button {
                store.send(.renameTapped(item))
            } label: {
                Label { Text(L10n.Browse.actionRename) } icon: { IconKit.rename }
            }
            .tint(.primaryDS)
        }
        if store.access?.canWrite ?? false {
            // Extract only offers `.zip` — the server's own extract route 415s anything else
            // ("Only .zip archives are supported"), `.rar` included despite this app being
            // able to browse rar contents client-side.
            if item.kind.lowercased() == "zip" {
                Button {
                    store.send(.extractZipTapped(item))
                } label: {
                    Label { Text(L10n.Browse.actionExtract) } icon: { IconKit.extract }
                }
                .tint(.primaryDS)
            }
            Button {
                store.send(.compressTapped(item))
            } label: {
                Label { Text(L10n.Browse.actionCompress) } icon: { IconKit.archiveDocument }
            }
            .tint(.primaryDS)
        }
        // Copy needs no permission on this folder (the server checks the destination on
        // paste); move has to delete the original, so it mirrors the web client's
        // `canWrite && canDelete` gate. A lone root location has nowhere to go and can't be
        // left absent, so neither is offered for it.
        if !isSoleRootLocation(item) {
            Button {
                store.send(.copyTapped(item), animation: .default)
            } label: {
                Label { Text(L10n.Browse.actionCopy) } icon: { IconKit.copy }
            }
            .tint(.primaryDS)
            if (store.access?.canWrite ?? false) && (store.access?.canDelete ?? false) {
                Button {
                    store.send(.moveTapped(item), animation: .default)
                } label: {
                    Label { Text(L10n.Browse.actionMove) } icon: { IconKit.move }
                }
                .tint(.primaryDS)
            }
        }
        if store.access?.canDownload ?? false {
            Button {
                store.send(.downloadTapped(item, .documents, removeArchiveAfterDownload: removeArchiveAfterDownload))
            } label: {
                Label { Text(L10n.Browse.actionDownload) } icon: { IconKit.download }
            }
            .tint(.primaryDS)
        }
        // Only folders can be favorited — the server 400s on anything else.
        if item.isDirectory {
            Button {
                store.send(.favoriteToggleButtonTapped(item))
            } label: {
                if store.favoritePaths.contains(item.id) {
                    Label { Text(L10n.Browse.actionRemoveFromFavorites) } icon: { IconKit.starFill }
                } else {
                    Label { Text(L10n.Browse.actionAddToFavorites) } icon: { IconKit.star }
                }
            }
            .tint(.primaryDS)
        }
        if store.access?.canShare ?? false {
            Button {
                shareTarget = item
            } label: {
                Label { Text(L10n.Browse.actionShare) } icon: { IconKit.shareLink }
            }
            .tint(.primaryDS)
        }
        if store.access?.canDelete ?? false {
            Button(role: .destructive) {
                store.send(.deleteTapped(item))
            } label: {
                Label { Text(L10n.Browse.actionDelete) } icon: { IconKit.delete }
            }
            .tint(.negative)
        }
    }

    /// Which branch of `overlayStateContent` is currently showing — a plain discriminant so
    /// the overlay can cross-fade between states instead of hard-cutting between them.
    private enum OverlayState: Hashable {
        case none, error, empty, searchingEverywhere, noResults
    }

    /// A fetch with nothing yet to show: the first load of this folder (including the frame
    /// before `onAppear` starts it) or a retry after a failed first load. Drives the loading
    /// skeleton and suppresses the empty state so a fresh folder never flashes "folder is
    /// empty" for a frame.
    private var isInitialLoad: Bool {
        (store.isLoading || !store.hasLoaded) && store.items.isEmpty && store.errorMessage == nil
    }

    private var overlayState: OverlayState {
        if store.errorMessage != nil {
            .error
        } else if store.hasLoaded && !store.isSearching && store.displayedItems.isEmpty {
            .empty
        } else if store.isSearching && store.searchScope == .everywhere && store.isSearchingEverywhere {
            .searchingEverywhere
        } else if store.isSearching, let results = store.displayedSearchResults, results.isEmpty {
            .noResults
        } else {
            .none
        }
    }

    @ViewBuilder
    private var overlayStateContent: some View {
        switch overlayState {
        case .searchingEverywhere:
            ProgressView()
                .transition(.opacity)
        case .error:
            if let errorMessage = store.errorMessage {
                EmptyStateView(icon: IconKit.warning, message: errorMessage) {
                    store.send(.refreshButtonTapped)
                }
                    .transition(.opacity)
            }
        case .empty:
            VStack(spacing: Constants.emptyUploadButtonTopSpacing) {
                EmptyStateView(icon: IconKit.folder, message: L10n.EmptyState.folderEmpty)
                if !store.isSelecting && canUploadHere {
                    emptyStateUploadButton
                }
            }
            .transition(.opacity)
        case .noResults:
            noResultsState
                .transition(.opacity)
        case .none:
            EmptyView()
        }
    }

    private var listContent: some View {
        List {
            Section {
                if store.isSearching {
                    searchResultRows
                } else {
                    folderItemRows
                }
            }
            pasteTargetRow
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .backgroundGradient()
        .safeAreaPadding(.bottom, bottomChromeClearance)
        .animation(
            .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
            value: store.displayedItems
        )
        .animation(
            .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
            value: store.displayedSearchResults
        )
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: Constants.gridSpacing) {
                if store.isSearching {
                    ForEach(store.displayedSearchResults ?? []) { result in
                        Button {
                            store.send(.searchResultTapped(result))
                        } label: {
                            GridCellView(name: result.name, isDirectory: result.isDirectory, isFavorite: store.favoritePaths.contains(result.id), kind: searchResultKind(result))
                                .dsCard(padding: Constants.gridCellPadding)
                        }
                        .buttonStyle(DSHapticButtonStyle())
                    }
                } else {
                    ForEach(store.displayedItems) { item in
                        Button {
                            if store.isSelecting {
                                store.send(.itemSelectionToggled(item.id))
                            } else {
                                handleTap(item)
                            }
                        } label: {
                            GridCellView(
                                item: item,
                                isFavorite: store.favoritePaths.contains(item.id),
                                serverURL: store.serverURL,
                                showThumbnails: store.preferences.showThumbnails,
                                iconSize: thumbnailSize.iconSize
                            )
                            .dsCard(padding: Constants.gridCellPadding)
                            .overlay(alignment: .topLeading) {
                                if store.isSelecting {
                                    DSSelectionIndicator(isSelected: store.selectedItemIDs.contains(item.id))
                                }
                            }
                        }
                        .buttonStyle(DSHapticButtonStyle())
                        .hapticFeedback(.selection, trigger: store.selectedItemIDs.contains(item.id))
                        .contextMenu {
                            if !store.isSelecting {
                                fileActionsContextMenu(for: item)
                            }
                        }
                    }
                }
            }
            .padding(Constants.gridSpacing)
            .animation(
                .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
                value: store.displayedItems
            )
            .animation(
                .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
                value: store.displayedSearchResults
            )
            pasteTargetArea
        }
        .backgroundGradient()
        .safeAreaPadding(.bottom, bottomChromeClearance)
    }

    /// Invisible long-press target filling the space past the last row — a plain
    /// `.contextMenu` on the whole list/scroll container lifts a snapshot of the entire list
    /// on long-press, which reads as the list jumping. Scoping it to this transparent trailing
    /// area keeps the list itself still. Present only while something is staged, so an empty
    /// menu never opens.
    @ViewBuilder
    private var pasteTargetRow: some View {
        if store.clipboard != nil && !store.directoryPath.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: Constants.pasteTargetMinHeight)
                .contentShape(Rectangle())
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .contextMenu { pasteEmptySpaceMenu }
        }
    }

    @ViewBuilder
    private var pasteTargetArea: some View {
        if store.clipboard != nil && !store.directoryPath.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: Constants.pasteTargetMinHeight)
                .contentShape(Rectangle())
                .contextMenu { pasteEmptySpaceMenu }
        }
    }

    /// Bottom scroll clearance for the chrome floating under this list: the breadcrumb bar
    /// (`BrowseTabView`/`FavoritesView`, pushed screens only — the root's `directoryPath` is
    /// always empty) and the app-level upload progress bar while it's showing. Both are placed
    /// by ancestors a `List` inside a pushed `navigationDestination` doesn't reliably respect.
    private var bottomChromeClearance: CGFloat {
        (store.directoryPath.isEmpty ? 0 : BrowseBreadcrumbBarMetrics.height)
            + (isUploadBarVisible ? uploadBarHeight + UploadBarChrome.gap : 0)
    }

    /// A top-level location (root screen) that is the only one there: it has nowhere to be
    /// copied or moved to, and can't be left absent, so the transfer actions are hidden.
    private func isSoleRootLocation(_ item: FileItem) -> Bool {
        store.directoryPath.isEmpty && item.path.isEmpty && store.items.count <= 1
    }

    /// Gates the `+` upload menu on the folder's own `FileAccess.canUpload`. Defaults to
    /// allowed while access is still loading — the first browse response fills it in.
    private var canUploadHere: Bool {
        store.access?.canUpload ?? true
    }

    /// The empty folder's call to action: the same camera / Photos / Files menu as the `+`,
    /// behind an accent pill so a first time user has somewhere obvious to start.
    private var emptyStateUploadButton: some View {
        UploadSourceMenu(
            label: {
                HStack(spacing: .space8) {
                    IconKit.upload
                    Text(L10n.Uploads.menuTitle)
                }
                .type(.label3)
                .foregroundStyle(Color.black)
                .frame(height: Constants.emptyUploadButtonHeight)
                .padding(.horizontal, Constants.emptyUploadButtonHPadding)
                .background(Capsule().fill(Color.accent))
            },
            isFilesPickerPresented: $isFilesPickerPresented,
            isPhotosPickerPresented: $isPhotosPickerPresented,
            isCameraPresented: $isCameraPresented,
            isCameraDeniedAlertPresented: $isCameraDeniedAlertPresented
        )
        .accessibilityLabel(L10n.Uploads.menuTitle)
    }

    /// Whether the current folder is a legitimate paste target for the staged clipboard —
    /// gates the "Paste" action in the `…` menu.
    private var canPasteIntoCurrentFolder: Bool {
        store.clipboard?.canPaste(into: store.directoryPath, canWrite: store.access?.canWrite ?? false) ?? false
    }

    /// "Paste" for a single staged item, "Paste N items" past that.
    private var pasteActionTitle: String {
        let count = store.clipboard?.items.count ?? 0
        return count <= 1 ? L10n.Browse.actionPaste : L10n.Browse.actionPasteCount(count)
    }

    /// Long-press menu for the empty space in the list/grid — only present while something is
    /// staged, so an empty menu never opens. Mirrors the `…` menu's paste/clear pair.
    @ViewBuilder
    private var pasteEmptySpaceMenu: some View {
        if store.clipboard != nil && !store.directoryPath.isEmpty {
            Button {
                store.send(.pasteTapped(keepItemsAfterCopy: keepClipboardAfterCopy), animation: .default)
            } label: {
                Label { Text(L10n.Browse.actionPasteHere) } icon: { IconKit.paste }
            }
            .disabled(!canPasteIntoCurrentFolder)
            Button {
                store.send(.clipboardCleared, animation: .default)
            } label: {
                Label { Text(L10n.Browse.actionClearClipboard) } icon: { IconKit.close }
            }
        }
    }

    @ViewBuilder
    private var folderItemRows: some View {
        // `store.displayedItems` filters + sorts on every read — bind it once here rather than
        // re-deriving it per row (the separator checks below alone made it O(n^2 log n)).
        let items = store.displayedItems
        let firstItemID = items.first?.id
        let lastItemID = items.last?.id
        ForEach(items) { item in
            Button {
                if store.isSelecting {
                    store.send(.itemSelectionToggled(item.id))
                } else {
                    handleTap(item)
                }
            } label: {
                HStack(spacing: .space12) {
                    if store.isSelecting {
                        DSSelectionIndicator(isSelected: store.selectedItemIDs.contains(item.id))
                    }
                    FileRowView(
                        item: item,
                        isFavorite: store.favoritePaths.contains(item.id),
                        serverURL: store.serverURL,
                        showThumbnails: store.preferences.showThumbnails
                    )
                }
            }
            .buttonStyle(DSHapticButtonStyle())
            .hapticFeedback(.selection, trigger: store.selectedItemIDs.contains(item.id))
            .contextMenu {
                if !store.isSelecting {
                    fileActionsContextMenu(for: item)
                }
            }
            .listRowBackground(Color.backgroundSecondary)
            .swipeActions(edge: .trailing) {
                if !store.isSelecting {
                    if store.access?.canDelete ?? false {
                        Button {
                            store.send(.deleteTapped(item))
                        } label: {
                            IconKit.delete
                        }
                        .tint(.negative)
                    }
                    // Only folders can be favorited — the server 400s on anything else.
                    if item.isDirectory {
                        Button {
                            store.send(.favoriteToggleButtonTapped(item))
                        } label: {
                            store.favoritePaths.contains(item.id) ? IconKit.starFill : IconKit.star
                        }
                        .tint(.accent)
                    }
                    if store.access?.canWrite ?? false {
                        Button {
                            store.send(.renameTapped(item))
                        } label: {
                            IconKit.rename
                        }
                        .tint(.positive)
                    }
                }
            }
            .listRowSeparator(item.id == firstItemID ? .hidden : .visible, edges: .top)
            .listRowSeparator(item.id == lastItemID ? .hidden : .visible, edges: .bottom)
        }
    }

    @ViewBuilder
    private var searchResultRows: some View {
        let results = store.displayedSearchResults ?? []
        ForEach(results) { result in
            Button {
                store.send(.searchResultTapped(result))
            } label: {
                FileRowView(name: result.name, isDirectory: result.isDirectory, subtitle: result.matchLine, isFavorite: store.favoritePaths.contains(result.id), kind: searchResultKind(result))
            }
            .buttonStyle(DSHapticButtonStyle())
            .listRowBackground(Color.backgroundSecondary)
            .listRowSeparator(result.id == results.first?.id ? .hidden : .visible, edges: .top)
            .listRowSeparator(result.id == results.last?.id ? .hidden : .visible, edges: .bottom)
        }
    }

    @ViewBuilder
    private var noResultsState: some View {
        VStack(spacing: Constants.emptyStateSpacing) {
            IconKit.search
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Constants.emptyStateIconSize, height: Constants.emptyStateIconSize)
            Text(L10n.Browse.searchNoMatchesInFolder(store.searchQuery))
                .type(.body1(.semibold), style: .secondary)
            if store.searchScope == .thisFolder {
                DSButton(L10n.Browse.searchEverywhere,
                         icon: IconKit.search,
                         style: .secondary,
                         size: .small,
                         isLoading: false, action: {
                        store.send(.searchScopeChanged(.everywhere))
                })
                .padding(.top, Constants.emptyStateSpacing)
            }
        }
        .padding(.space16)
        .multilineTextAlignment(.center)
    }
}

@MainActor
private func browsePreview(
    directoryPath: String = "Documents",
    configureClient: (inout FilesClient) -> Void = { _ in },
    mutateState: (inout BrowseFeature.State) -> Void = { _ in }
) -> some View {
    var state = BrowseFeature.State(
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        directoryPath: directoryPath,
        title: L10n.Browse.navigationTitle
    )
    mutateState(&state)
    var client = FilesClient.previewValue
    configureClient(&client)
    let store = Store(initialState: state) {
        BrowseFeature()
    } withDependencies: {
        $0.filesClient = client
    }
    return NavigationStack {
        BrowseContentView(store: store)
            .navigationTitle(L10n.Browse.navigationTitle)
    }
}

private let browsePreviewItems: [FileItem] = [
    FileItem(name: "Projects", path: "Documents", dateModified: Date(), size: 0, kind: "directory"),
    FileItem(name: "budget.xlsx", path: "Documents", dateModified: Date(), size: 44_000, kind: "xlsx"),
    FileItem(name: "notes.txt", path: "Documents", dateModified: Date(), size: 1_200, kind: "txt"),
    FileItem(name: "cover.jpg", path: "Documents", dateModified: Date(), size: 2_400_000, kind: "jpg", supportsThumbnail: true),
]

private let browsePreviewEmptyAccess = FileAccess(
    canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true
)

#Preview("Browse — content") {
    browsePreview(mutateState: { $0.items = IdentifiedArray(uniqueElements: browsePreviewItems) })
}

#Preview("Browse — loading") {
    browsePreview(mutateState: { $0.isLoading = true })
}

#Preview("Browse — empty folder") {
    browsePreview(
        configureClient: { $0.browse = { _, path in BrowseResult(items: [], access: browsePreviewEmptyAccess, path: path) } }
    )
}

#Preview("Browse — error") {
    browsePreview(mutateState: { $0.errorMessage = L10n.EmptyState.loadFailed })
}

#Preview("Browse — no search results") {
    browsePreview(mutateState: {
        $0.searchQuery = "vacation"
        $0.searchResults = []
    })
}

#Preview("Browse — searching everywhere") {
    browsePreview(mutateState: {
        $0.searchQuery = "vacation"
        $0.searchScope = .everywhere
        $0.isSearchingEverywhere = true
    })
}

#Preview("Browse — delete alert, linked shares") {
    browsePreview(mutateState: {
        $0.items = IdentifiedArray(uniqueElements: browsePreviewItems)
        $0.deleteConfirmationItem = browsePreviewItems[1]
        $0.deleteImpactCheck = .loaded(DeleteImpact(shareCount: 2))
    })
}

#Preview("Browse — delete alert, share check unavailable") {
    browsePreview(mutateState: {
        $0.items = IdentifiedArray(uniqueElements: browsePreviewItems)
        $0.deleteConfirmationItem = browsePreviewItems[1]
        $0.deleteImpactCheck = .unavailable
    })
}
