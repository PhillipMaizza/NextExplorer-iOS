import CoreModels
import Foundation

/// What the selection menu offers, worked out from the screen's state so it can be tested apart from
/// the view.
extension BrowseFeature.State {
    /// Rename only makes sense for a single target: `nil` (hiding the toolbar icon) for
    /// zero or multiple selected items.
    var singleSelectedItem: FileItem? {
        guard selectedItemIDs.count == 1, let id = selectedItemIDs.first else { return nil }
        return items[id: id]
    }

    /// What the selection menu offers for the items picked now.
    var selectionAvailability: SelectionActionsMenu.Availability {
        // Device content offers only what works on kept files, and only once every pick is kept.
        let isDevice = showsDeviceContent
        let isAllKept = selectedItemIDs.allSatisfy(offlineItemIDs.contains)
        return SelectionActionsMenu.Availability(
            single: singleSelectedItem,
            canGetInfo: !isDevice,
            canWrite: access?.canWrite ?? false,
            canShare: !isDevice && (access?.canShare ?? false),
            sharesKeptFiles: isDevice && isAllKept && Self.canShareKeptFiles && selectedItems
                .contains { !$0.isDirectory },
            canTransfer: !isDevice && isTransferActionVisible,
            canMove: isTransferActionVisible && (access?.canWrite ?? false) && (access?.canDelete ?? false),
            canDelete: isDeleteActionVisible,
            canSave: isSaveActionVisible && (!isDevice || isAllKept),
            canKeepOffline: (access?.canDownload ?? false) && (!isDevice || isAllKept),
            offlineAction: selectedOfflineAction,
            canFavorite: isFavoriteActionVisible,
            isAllFavorite: isEntireSelectionAlreadyFavorited,
            hasLoadedFavorites: hasLoadedFavorites
        )
    }

    /// The selected items, in listing order.
    var selectedItems: [FileItem] {
        items.filter { selectedItemIDs.contains($0.id) }
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
        !showsDeviceContent && !selectedItemIDs.isEmpty && selectedItemIDs.allSatisfy { id in
            items[id: id]?.isDirectory ?? false
        }
    }

    /// Filled when tapping the toolbar star would unfavorite the whole selection, matching
    /// the single item context menu icon's own filled or outline convention.
    var isEntireSelectionAlreadyFavorited: Bool {
        !selectedItemIDs.isEmpty && selectedItemIDs.allSatisfy(favoritePaths.contains)
    }

    var isDownloadActionVisible: Bool {
        !selectedItemIDs.isEmpty && (access?.canDownload ?? false)
    }

    var isSaveActionVisible: Bool {
        isDownloadActionVisible && items.contains {
            selectedItemIDs.contains($0.id) && SaveActionStyle.isAvailable(for: $0.isDirectory)
        }
    }

    var isDeleteActionVisible: Bool {
        !selectedItemIDs.isEmpty && (access?.canDelete ?? false)
    }

    /// Copy/Move from the selection toolbar: available whenever anything is selected, except
    /// for a lone root location (same rule the single item context menu enforces via
    /// `isSoleRootLocation`). Copy needs no permission; the Move button adds a
    /// `canWrite && canDelete` gate at its site.
    var isTransferActionVisible: Bool {
        !selectedItemIDs.isEmpty && !(directoryPath.isEmpty && items.count <= 1)
    }
}
