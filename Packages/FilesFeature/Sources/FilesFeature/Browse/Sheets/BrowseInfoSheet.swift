import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// Distinct identities for "still loading" vs. "have a result", so swapping between the
/// two (once the fetch resolves) is a genuinely fresh sheet presentation rather than an
/// in-place content change: see `FileInfoLoadingSheet`'s doc comment for why that
/// matters for getting the right height.
enum BrowseInfoSheetPhase: Identifiable, Equatable {
    case loading(FileItem)
    case result(FileItem)

    @MainActor
    init?(store: StoreOf<BrowseFeature>) {
        guard let item = store.infoItem else { return nil }
        guard store.infoMetadata != nil || store.infoErrorMessage != nil else {
            self = .loading(item)
            return
        }
        self = .result(item)
    }

    var id: String {
        switch self {
        case let .loading(item): "loading-\(item.id)"
        case let .result(item): "result-\(item.id)"
        }
    }
}

struct BrowseInfoSheetContent: View {
    let store: StoreOf<BrowseFeature>
    let phase: BrowseInfoSheetPhase

    var body: some View {
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
}
