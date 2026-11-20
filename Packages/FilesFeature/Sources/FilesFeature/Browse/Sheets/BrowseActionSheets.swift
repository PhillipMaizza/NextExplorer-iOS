import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import FolderPickerFeature
import Localization
import SwiftUI

/// The sheets and alerts a file action raises, over whichever surface is frontmost: the list, or
/// the preview cover. One reducer state drives both, so each presentation is bound only while its
/// surface is the one on screen.
struct BrowseActionSheets: ViewModifier {
    @Dependency(\.date) private var date
    @Bindable var store: StoreOf<BrowseFeature>
    let inPreview: Bool
    @Binding var shareTarget: FileItem?
    /// From the folder picker appearing until its sheet has fully closed.
    @Binding var isDestinationPickerOnScreen: Bool

    private var isFrontmost: Bool {
        (store.previewItem != nil) == inPreview
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: destinationPickerBinding, onDismiss: { isDestinationPickerOnScreen = false }) { pickerStore in
                DestinationPickerView(store: pickerStore)
                    .onAppear { isDestinationPickerOnScreen = true }
            }
            .dsAlert(isPresented: deleteBinding) { deleteSheet }
            .dsAlert(isPresented: keptBinding) { keptSheet }
            .dsSheet(item: renameBinding) { renameSheet($0) }
            .dsSheet(item: shareBinding) { shareSheet($0) }
            .dsAlert(isPresented: transferConflictBinding) {
                DSAlertSheet.transferConflict(store.transferConflict) { choice in
                    store.send(.transferConflictResolved(choice), animation: choice == nil ? nil : DSMotion.listDiff)
                }
            }
        #if os(iOS)
            .dsSheet(item: infoBinding) { BrowseInfoSheetContent(store: store, phase: $0) }
        #endif
    }

    /// The folder picker over whichever surface is frontmost.
    private var destinationPickerBinding: Binding<StoreOf<DestinationPickerFeature>?> {
        let scoped = $store.scope(state: \.destinationPicker, action: \.destinationPicker)
        return Binding(
            get: { isFrontmost ? scoped.wrappedValue : nil },
            set: { scoped.wrappedValue = $0 }
        )
    }

    /// No op setter: the sheet is dismiss disabled and only closes through one of
    /// `DSAlertSheet`'s own buttons, which drive the reducer directly.
    private var deleteBinding: Binding<Bool> {
        Binding(
            get: {
                store.deleteConfirmationItem != nil && isFrontmost && BrowseDeleteCopy.isReady(store.deleteImpactCheck)
            },
            set: { _ in }
        )
    }

    private var deleteSheet: DSAlertSheet {
        // A single item preview dismisses the cover and defers the delete so the row animates out
        // on the list. The gallery (and the list) delete in place. Either way
        // `deleteConfirmationItem` clears synchronously, so no binding flicker.
        let fromPreview = inPreview && !store.isPreviewInGallery
        return BrowseDeleteCopy.alert(
            title: BrowseDeleteCopy.title(store),
            check: store.deleteImpactCheck,
            onConfirm: { store.send(fromPreview ? .deleteConfirmedFromPreview : .deleteConfirmed) },
            onDeletePermanently: { store.send(.deletePermanentlyConfirmed(fromPreview: fromPreview)) },
            onDismiss: { store.send(.deleteCancelled) }
        )
    }

    /// Up once a delete left items the trash refused; only the surface on screen shows it.
    private var keptBinding: Binding<Bool> {
        Binding(get: { !store.keptDeletes.isEmpty && isFrontmost }, set: { _ in })
    }

    private var keptSheet: DSAlertSheet {
        BrowseDeleteCopy.keptAlert(
            store.keptDeletes,
            onDeletePermanently: { store.send(.keptDeletePermanentlyConfirmed) },
            onDismiss: { store.send(.keptDeleteDismissed) }
        )
    }

    /// Drives the rename `NameInputSheet`; a swipe down dismiss routes back through the reducer
    /// so `renameSheetItem` clears. The reducer also nils it itself on a completed rename.
    private var renameBinding: Binding<FileItem?> {
        Binding(
            get: { isFrontmost && !(store.renamesInTable && !inPreview) ? store.renameSheetItem : nil },
            set: {
                if $0 == nil {
                    store.send(.renameCancelled)
                }
            }
        )
    }

    private func renameSheet(_ item: FileItem) -> some View {
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

    private var shareBinding: Binding<FileItem?> {
        Binding(get: { isFrontmost ? shareTarget : nil }, set: { shareTarget = $0 })
    }

    private func shareSheet(_ item: FileItem) -> some View {
        CreateShareLinkSheet(
            store: Store(
                initialState: CreateShareLinkFeature.State(
                    serverURL: store.serverURL,
                    itemName: item.name,
                    itemPath: item.path,
                    isDirectory: item.isDirectory,
                    now: date.now
                )
            ) {
                CreateShareLinkFeature()
            },
            onViewShares: { store.send(inPreview ? .goToSharedTabFromPreview : .delegate(.goToSharedTab)) }
        )
    }

    /// The button closures own dismissal (they clear `transferConflict`); the no op setter
    /// keeps a SwiftUI initiated dismiss from firing a second resolve into a torn down sheet.
    /// Waits for the folder picker to finish closing: a card can't present while the sheet under
    /// it is still on its way out, and would be dropped.
    private var transferConflictBinding: Binding<Bool> {
        Binding(
            get: { store.transferConflict != nil && !isDestinationPickerOnScreen && isFrontmost },
            set: { _ in }
        )
    }

    private var infoBinding: Binding<BrowseInfoSheetPhase?> {
        Binding(
            get: { isFrontmost ? BrowseInfoSheetPhase(store: store) : nil },
            set: {
                if $0 == nil {
                    store.send(.infoDismissed)
                }
            }
        )
    }
}

/// The sheets and alerts only the list raises: sort, new folder, new file, bulk delete, and the
/// offline removal and kept file share prompts.
struct BrowseListSheets: ViewModifier {
    @Bindable var store: StoreOf<BrowseFeature>
    @Binding var isSortSheetPresented: Bool

    func body(content: Content) -> some View {
        content
            .dsAlert(isPresented: Binding(
                get: { store.bulkDeletePhase.isConfirming && BrowseDeleteCopy.isReady(store.deleteImpactCheck) },
                set: { _ in }
            )) {
                BrowseDeleteCopy.alert(
                    title: BrowseDeleteCopy.bulkTitle(store),
                    check: store.deleteImpactCheck,
                    onConfirm: { store.send(.bulkDeleteConfirmed) },
                    onDeletePermanently: { store.send(.bulkDeletePermanentlyConfirmed) },
                    onDismiss: { store.send(.bulkDeleteCancelled) }
                )
            }
            .dsSheet(isPresented: $isSortSheetPresented) {
                SortSheet(
                    options: BrowseFeature.SortOption.allCases,
                    directions: BrowseFeature.SortDirection.allCases,
                    sortOption: store.sortOption,
                    sortDirection: store.sortDirection,
                    optionIcon: { $0.icon },
                    optionTitle: { $0.title },
                    directionIcon: { $0.icon },
                    directionTitle: { $0.title },
                    onSelectOption: { store.send(.sortOptionChanged($0), animation: DSMotion.listChange) },
                    onSelectDirection: { store.send(.sortDirectionChanged($0), animation: DSMotion.listChange) },
                    onDismiss: { isSortSheetPresented = false }
                )
            }
            .dsSheet(isPresented: newFolderBinding) {
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
            .dsSheet(isPresented: newFileBinding) {
                NameInputSheet(
                    icon: IconKit.newFile,
                    title: L10n.Browse.newFileTitle,
                    placeholder: L10n.Browse.newFilePlaceholder,
                    confirmTitle: L10n.Browse.newFolderConfirm,
                    isBusy: store.isPerformingFileAction,
                    additionalRule: { [extensions = store.newFileServerExtensions] name in
                        EditableTextFiles.isEditable(name: name, serverExtensions: extensions)
                            ? nil
                            : L10n.Browse.newFileTypeHint
                    },
                    capitalizesWords: false,
                    onConfirm: { store.send(.newFileConfirmed($0)) },
                    onCancel: { store.send(.newFileCancelled) }
                )
            }
            .offlineRemovalAlert(
                store.previewItem == nil ? store.offlineRemoval : nil,
                onConfirm: { store.send(.offlineRemovalConfirmed, animation: DSMotion.listDiff) },
                onCancel: { store.send(.offlineRemovalCancelled) }
            )
        #if os(iOS)
            .keptFilesShareSheet(store.keptShare) { store.send(.keptShareDismissed) }
        #endif
    }

    private var newFileBinding: Binding<Bool> {
        Binding(
            get: { store.isNewFileSheetPresented },
            set: {
                if !$0 {
                    store.send(.newFileCancelled)
                }
            }
        )
    }

    private var newFolderBinding: Binding<Bool> {
        Binding(
            get: { store.isNewFolderSheetPresented },
            set: {
                if !$0 {
                    store.send(.newFolderCancelled)
                }
            }
        )
    }
}
