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
    func isOpening(_ id: String, in store: StoreOf<BrowseFeature>) -> Bool {
        store.previewItem?.id == id && !store.isPreviewContentReady
    }
}

extension BrowseFeature.State {
    /// Root only, outside search and select mode: the account's private folder is not a volume,
    /// so it is not something a bulk action over the listing should touch.
    var showsPersonalSpace: Bool {
        directoryPath.isEmpty && isPersonalSpaceEnabled && !isSearching && !isSelecting
    }

    /// The Mac folder table renames in place; search results and previews keep the sheet.
    var renamesInTable: Bool {
        #if os(macOS)
            previewItem == nil && !isSearching
        #else
            false
        #endif
    }
}
