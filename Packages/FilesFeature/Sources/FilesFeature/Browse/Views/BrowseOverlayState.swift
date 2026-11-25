import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// Which branch of `BrowseOverlayContent` is currently showing: a plain discriminant so the
/// overlay can cross fade between states instead of hard cutting between them.
enum BrowseOverlayState: Hashable {
    case none, error, empty, searching, searchFailed, noResults

    @MainActor
    init(store: StoreOf<BrowseFeature>) {
        if store.phase.errorMessage != nil {
            self = .error
        } else if store.isListingKnown, !store.isSearching, !store.hasDisplayedItems {
            self = .empty
        } else if store.isSearchPending, store.displayedSearchResults?.isEmpty ?? true {
            // A recursive backend search is in flight with nothing to show yet (the instant
            // matches found nothing local): placeholders rather than a flash of "no results".
            self = .searching
        } else if store.searchFailureMessage != nil, store.displayedSearchResults?.isEmpty ?? true {
            self = .searchFailed
        } else if store.isSearching, let results = store.displayedSearchResults, results.isEmpty {
            switch store.elsewherePhase {
            case .loading: self = .searching
            case .loaded where store.isShowingElsewhereResults: self = .none
            default: self = .noResults
            }
        } else {
            self = .none
        }
    }
}

/// What fills the folder when there is nothing to list: the error, the empty folder and its upload
/// call to action, the searching placeholder, a failed search or no matches.
struct BrowseOverlayContent<Skeleton: View, EmptyFolder: View>: View {
    let store: StoreOf<BrowseFeature>
    @ViewBuilder let skeleton: () -> Skeleton
    @ViewBuilder let emptyFolder: () -> EmptyFolder

    var body: some View {
        switch BrowseOverlayState(store: store) {
        case .searching:
            // The shape of the answer to come, like a folder's first load, rather than a second
            // spinner beside the one in the search field.
            skeleton()
                .transition(.opacity)
        case .error:
            if let errorMessage = store.phase.errorMessage {
                EmptyStateView(
                    icon: IconKit.warning,
                    message: errorMessage
                ) {
                    store.send(.refreshButtonTapped)
                }
                .transition(.opacity)
            }
        case .empty:
            emptyFolder()
                .transition(.opacity)
        case .searchFailed:
            if let message = store.searchFailureMessage {
                EmptyStateView(icon: IconKit.warning, message: message) {
                    store.send(.searchRetryTapped)
                }
                .transition(.opacity)
            }
        case .noResults:
            BrowseNoResultsState(store: store)
                .transition(.opacity)
        case .none:
            EmptyView()
        }
    }
}
