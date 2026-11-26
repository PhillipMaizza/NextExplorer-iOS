import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import SwiftUI

/// What a row or cell needs to take part in the preview's zoom morph.
struct BrowsePreviewSource {
    let namespace: Namespace.ID
    let visibility: PreviewSourceVisibility

    func matched(_ id: String) -> PreviewMatchedSource {
        PreviewMatchedSource(id: id, namespace: namespace, visibility: visibility)
    }

    /// The row whose file is still being fetched for the preview, so it shows its spinner.
    @MainActor
    func isOpening(_ id: String, in store: StoreOf<BrowseFeature>) -> Bool {
        store.previewItem?.id == id && !store.isPreviewContentReady
    }
}

extension BrowseFeature.State {
    /// Root only, outside search and select mode: the account's private folder is not a volume,
    /// so it is not something a bulk action over the listing should touch.
    var shouldShowPersonalSpace: Bool {
        directoryPath.isEmpty && isPersonalSpaceEnabled && !isSearching && !isSelecting
    }

    var hasNothingToList: Bool {
        !hasDisplayedItems && !shouldShowPersonalSpace
    }

    var rootEmptyGuide: MacListGuide? {
        guard directoryPath.isEmpty else { return nil }
        return isUserVolumesEnabled && !isAdmin ? .browseRootUnassigned : .browseRootNoVolumes
    }

    /// The Trash button sits in the root's toolbar on iPhone and iPad; the Mac has a sidebar row instead.
    var shouldShowTrashButton: Bool {
        #if os(iOS)
            directoryPath.isEmpty && isTrashAvailable && !isSearching && !isSelecting
        #else
            false
        #endif
    }

    /// The Mac folder table renames in place; search results and previews keep the sheet.
    var shouldRenameInTable: Bool {
        #if os(macOS)
            previewItem == nil && !isSearching
        #else
            false
        #endif
    }
}
