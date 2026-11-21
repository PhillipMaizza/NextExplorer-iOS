import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import FolderPickerFeature
import Foundation
import Localization
import NetworkClient
import ShareUploads
import SwiftUI

extension BrowseFeature {
    /// Opening a row, searching the folder or everywhere, and sorting.
    func reduceSearch(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case let .rowTapped(item):
            guard item.isDirectory else {
                // Google Drive stub files (`.gsheet`, `.gdoc`, …) link out to a real
                // Google document: open that, don't show the JSON stub.
                if item.isGoogleDocsPointer {
                    return openGoogleDocsPointer(serverURL: state.serverURL, item: item)
                }
                // Sets `previewItem` unconditionally so the viewer presents immediately.
                // • Files the app has no viewer for (archives it can't browse, known
                //   binaries, undecodable video) get `UnsupportedFilePreviewView`: the
                //   name/type/size + download/share actions, no fetch.
                // • Streamable media (video/audio) plays live from `FilesClient.previewURL`.
                // • Images/RAW load themselves per page in the gallery view.
                // • Browsable archives (.zip/.rar) list themselves in `ArchiveBrowserView`.
                // Only PDFs and plain text files need a fetch here.
                state.previewItem = item
                state.isPreviewEditing = false
                switch PreviewKind(item) {
                case .unsupported, .archive, .media, .image:
                    return .none
                case .document:
                    return loadPreview(&state, item: item)
                case .text:
                    return loadTextContent(&state, item: item)
                }
            }
            return .send(.delegate(.openFolder(item)))

        case let .searchQueryChanged(query):
            // A focus change or keyboard dismiss resends the same text through the field's
            // binding, and a typed space leaves the term the server reads unchanged; rerunning
            // `search` would reset results to the local prefill and refetch, flashing the
            // list. Only a new term searches again; the pending one keeps its debounce.
            let isNewTerm = SearchTerm(query) != SearchTerm(state.searchQuery)
            state.searchQuery = query
            guard isNewTerm else { return .none }
            state.searchLimit = FilesClient.searchLimitSteps[0]
            return search(&state)

        case let .searchScopeChanged(scope):
            guard scope != state.searchScope else { return .none }
            state.searchScope = scope
            state.searchLimit = FilesClient.searchLimitSteps[0]
            // Another folder to search from: what was saved below the old one says nothing.
            state.searchSavedItems = nil
            return .merge(.cancel(id: CancelID.searchSavedItems), search(&state, isDebounced: false))

        case .searchShowMoreTapped:
            guard state.canShowMoreSearchResults else { return .none }
            state.searchLimit = FilesClient.searchLimitSteps.first { $0 > state.searchLimit } ?? state.searchLimit
            state.searchPhase = .loading
            return fetchSearchResults(state, isDebounced: false)

        case .searchRetryTapped:
            return refreshSearch(&state)

        case let .searchSavedItemsLoaded(items):
            savedSearchItemsLoaded(items, state: &state)
            return .none

        case let .searchCategoryToggled(category):
            if state.selectedSearchCategories.contains(category) {
                state.selectedSearchCategories.remove(category)
            } else {
                state.selectedSearchCategories.insert(category)
            }
            return .none

        case .searchFilterCleared:
            state.selectedSearchCategories = []
            return .none

        case let .folderCategoryToggled(category):
            if state.selectedFolderCategories.contains(category) {
                state.selectedFolderCategories.remove(category)
            } else {
                state.selectedFolderCategories.insert(category)
            }
            // A pick the filter hides is dropped, so a bulk action never reaches a file off screen.
            state.selectedItemIDs.formIntersection(state.displayedItems.ids)
            return .none

        case .folderFilterCleared:
            state.selectedFolderCategories = []
            return .none

        case let .searchResultTapped(result):
            guard !result.isDirectory else {
                // Opening a folder ends the search, as in Finder, so the search never carries
                // into the folder it opens.
                state.searchQuery = ""
                return .merge(
                    search(&state),
                    .send(.delegate(.openPath(path: result.id, title: result.name)))
                )
            }
            // The same preview routing a browse row tap uses.
            // A pinned copy opens first: the hit knows no size or date, so it takes the copy's own.
            let pinned = offlineFileStore.pinned(to: state.cacheScope)
            let item = pinned.matchingPinnedCopy(result.previewItem(openedAt: date.now))
            state.isPreviewOutsideListing = true
            // The hit is not in the listing the offline marks come from, so its preview would
            // offer to keep a file that already is. Marked here, its removal is offered instead.
            if pinned.pinnedRoots().contains(where: { $0.path == item.id }) {
                state.offlinePinnedItemIDs.insert(item.id)
                state.offlineItemIDs.insert(item.id)
            } else if pinned.coveringRoot(of: item.id) != nil {
                state.offlineItemIDs.insert(item.id)
            }
            return .send(.rowTapped(item))

        case let .searchResultsResponse(_, term) where term != SearchTerm(state.searchQuery).text:
            return state.searchPhase == .loading ? fetchSearchResults(state, isDebounced: false) : .none

        case let .searchResultsResponse(.success(page), term):
            state.searchPhase = .loaded
            state.searchResults = IdentifiedArray(page.items, id: \.id, uniquingIDsWith: { first, _ in first })
            state.searchAnsweredTerm = term
            state.searchShortfall = SearchShortfall(page)
            // Drop any selected category the new results no longer contain, so the filter
            // can't strand the list on an empty set the sheet doesn't even offer.
            state.selectedSearchCategories.formIntersection(Set(state.availableSearchCategories))
            return .none

        case let .searchResultsResponse(.failure(error), term):
            // Said under the results with Retry, otherwise a network blip during a search is
            // indistinguishable from a genuine empty result.
            state.searchPhase = .failed(searchFailureMessage(error))
            // Offline, the saved listings stand in (read now if this search has not yet).
            let readSaved = loadSavedSearchItemsIfNeeded(state)
            // This term's own answer (a failed refresh or Show more) stays; an earlier term's
            // gives way to this term's instant matches.
            guard state.searchAnsweredTerm != term else { return readSaved }
            state.searchResults = Self.instantMatches(state, query: term)
            state.searchAnsweredTerm = nil
            state.searchShortfall = nil
            return readSaved

        case let .sortOptionChanged(option):
            state.sortOption = option
            return .none

        case let .sortDirectionChanged(direction):
            state.sortDirection = direction
            return .none

        default:
            return .none
        }
    }
}
