import CoreModels
import Foundation

/// What the selection menu offers, worked out from the screen's state so it can be tested apart from
/// the view.
extension BrowseFeature.State {
    var isListingKnown: Bool {
        phase.hasLoaded || isShowingCachePaint
    }

    /// Rename only makes sense for a single target: `nil` (hiding the toolbar icon) for
    /// zero or multiple selected items.
    var singleSelectedItem: FileItem? {
        let selected = selectedItems
        return selected.count == 1 ? selected.first : nil
    }

    /// What the selection menu offers for the items picked now.
    var selectionAvailability: SelectionActionsMenu.Availability {
        // Device content offers only what works on kept files, and only once every pick is kept.
        let isDevice = shouldShowDeviceContent
        let picked = selectedItems
        let actions = actions(for: picked)
        let isAllKept = picked.allSatisfy { offlineItemIDs.contains($0.id) }
        return SelectionActionsMenu.Availability(
            single: picked.count == 1 ? picked.first : nil,
            canGetInfo: !isDevice,
            canWrite: actions.canRename,
            canDuplicate: actions.canDuplicate,
            canShare: actions.canShare,
            canShareKept: isDevice && isAllKept && Self.canShareKeptFiles && picked.contains { !$0.isDirectory },
            canTransfer: actions.canCopy,
            canCompress: actions.canCompress,
            canMove: actions.canMove,
            canDelete: actions.canDelete,
            canSave: isSaveActionVisible && (!isDevice || isAllKept),
            canKeepOffline: actions.canDownload && (!isDevice || isAllKept),
            offlineAction: selectedOfflineAction,
            canFavorite: isFavoriteActionVisible,
            isAllFavorite: isEntireSelectionAlreadyFavorited,
            hasLoadedFavorites: hasLoadedFavorites
        )
    }

    /// Select mode is offered only where a pick can lead to an action: device content acts on kept
    /// files alone, so a saved copy shown with no network and nothing kept in it has nothing to select.
    var canSelectItems: Bool {
        hasDisplayedItems && (!shouldShowDeviceContent || items.contains { offlineItemIDs.contains($0.id) })
    }

    var canMoveHere: Bool {
        access?.canDelete ?? false
    }

    /// Allowed while a live folder's access is still loading, so the `+` is there from the first
    /// frame. A screen of device content offers nothing to add, also before its access lands, so
    /// its toolbar never shows the `+` only to take it away again.
    func access(for item: FileItem) -> FileAccess? {
        item.path == directoryPath || item.id == directoryPath ? access : nil
    }

    private var mayAddBeforeAccess: Bool {
        !shouldShowDeviceContent && phase.errorMessage == nil
    }

    var canUploadHere: Bool {
        !directoryPath.isEmpty && (access?.canUpload ?? mayAddBeforeAccess)
    }

    var canCreateFileHere: Bool {
        access?.canCreateFile ?? mayAddBeforeAccess
    }

    var canCreateFolderHere: Bool {
        access?.canCreateFolder ?? mayAddBeforeAccess
    }

    /// The `+` appears when anything can be added here: an upload, a new folder or a new file.
    var canAddHere: Bool {
        canUploadHere || (!directoryPath.isEmpty && (canCreateFileHere || canCreateFolderHere))
    }

    /// The selected items on screen, in the order shown: every bulk action and count reads these, so a
    /// pick a setting has since hidden (hidden files turned off in another window) is never acted on.
    var selectedItems: [FileItem] {
        displayedItems.filter { selectedItemIDs.contains($0.id) }
    }

    /// The Mac's share menu needs a button to anchor to, so kept files are shared from iOS only.
    static var canShareKeptFiles: Bool {
        #if os(iOS)
            true
        #else
            false
        #endif
    }

    /// Only directories can be favorited, so a selection mixing a file in with a folder has
    /// no well defined bulk target: the icon disappears entirely rather than silently
    /// ignoring the file, which a merely disabled icon would leave ambiguous.
    var isFavoriteActionVisible: Bool {
        let picked = selectedItems
        return !shouldShowDeviceContent && !picked.isEmpty && picked.allSatisfy(\.isDirectory)
    }

    /// Filled when tapping the toolbar star would unfavorite the whole selection, matching
    /// the single item context menu icon's own filled or outline convention.
    var isEntireSelectionAlreadyFavorited: Bool {
        let picked = selectedItems
        return !picked.isEmpty && picked.allSatisfy { favoritePaths.contains($0.id) }
    }

    var isDownloadActionVisible: Bool {
        actions(for: selectedItems).canDownload
    }

    var isSaveActionVisible: Bool {
        isDownloadActionVisible && selectedItems.contains { SaveActionStyle.isAvailable(for: $0.isDirectory) }
    }

    var isDeleteActionVisible: Bool {
        actions(for: selectedItems).canDelete
    }

    /// Whether any pick is on screen: a selection only a setting has since hidden offers nothing.
    var hasSelectionOnScreen: Bool {
        !selectedItems.isEmpty
    }
}
