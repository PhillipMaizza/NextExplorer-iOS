import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// Search hits and browse rows share an `id` scheme (`path/name`), so `searchResultTapped`
/// builds a `FileItem` whose id matches the hit: the `.zoom` source and the opening
/// spinner can key off the same value.
private struct BrowseSearchResultCell: View {
    let store: StoreOf<BrowseFeature>
    let row: SearchResultItem
    let isGrid: Bool
    let source: BrowsePreviewSource

    var body: some View {
        Group {
            if isGrid {
                // A search hit reports no size of its own: it comes from this folder's listing or a
                // saved one, and a hit in neither says where it lives instead.
                let known = store.items[id: row.id] ?? store.searchSavedItems?[row.id]
                GridCellView(
                    name: row.name, isDirectory: row.isDirectory,
                    isFavorite: store.favoritePaths.contains(row.id), kind: row.displayKind,
                    size: known.flatMap { $0.isDirectory ? store.folderSizes[$0.id] : $0.size },
                    thumbnailFile: row.thumbnailFile,
                    serverURL: store.serverURL,
                    shouldShowThumbnails: store.preferences.shouldShowThumbnails,
                    matchedSource: source.matched(row.id),
                    isOpening: source.isOpening(row.id, in: store),
                    subtitle: known == nil ? searchResultLocation(row) : nil
                )
            } else {
                SearchResultRow(
                    result: row,
                    knownItem: store.items[id: row.id],
                    currentFolder: store.directoryPath,
                    isFavorite: store.favoritePaths.contains(row.id),
                    serverURL: store.serverURL,
                    shouldShowThumbnails: store.preferences.shouldShowThumbnails,
                    matchedSource: source.matched(row.id),
                    isOpening: source.isOpening(row.id, in: store)
                )
            }
        }
    }
}

private struct BrowseSearchResultActions: View {
    let store: StoreOf<BrowseFeature>
    let result: SearchResultItem

    var body: some View {
        SearchResultMenu(
            result: result,
            onOpen: { store.send(.searchResultTapped(result)) },
            onShowInFolder: { store.send(.searchResultEnclosingFolderTapped(result)) }
        )
    }
}

/// Search hits as grid tiles.
struct BrowseSearchResultCells: View {
    let store: StoreOf<BrowseFeature>
    let results: [SearchResultItem]
    let source: BrowsePreviewSource

    var body: some View {
        ForEach(results) { result in
            Button {
                store.send(.searchResultTapped(result))
            } label: {
                BrowseSearchResultCell(store: store, row: result, isGrid: true, source: source)
                    .dsGridTile()
            }
            .buttonStyle(DSPressableButtonStyle())
            .dsTapFlashSource()
            .contextMenu { BrowseSearchResultActions(store: store, result: result) }
        }
    }
}

struct BrowseSearchResultRows: View {
    let store: StoreOf<BrowseFeature>
    let results: [SearchResultItem]
    let source: BrowsePreviewSource

    var body: some View {
        ForEach(results) { result in
            DSFlashingListRow {
                Button {
                    store.send(.searchResultTapped(result))
                } label: {
                    BrowseSearchResultCell(store: store, row: result, isGrid: false, source: source)
                }
                .buttonStyle(DSPressableButtonStyle())
                .contextMenu { BrowseSearchResultActions(store: store, result: result) }
                .listRowSeparator(result.id == results.first?.id ? .hidden : .visible, edges: .top)
                .listRowSeparator(result.id == results.last?.id ? .hidden : .visible, edges: .bottom)
            }
        }
    }
}

/// The note under a search's results: why it is short, how to see more, search everywhere, retry.
struct BrowseSearchFooter: View {
    let store: StoreOf<BrowseFeature>

    var body: some View {
        SearchStatusFooter(
            message: Self.message(store),
            canShowMore: store.canShowMoreSearchResults && store.searchPhase != .loading
                && !store.isSearchingMyFilesAndVolumes,
            onShowMore: { store.send(.searchShowMoreTapped) },
            onSearchEverywhere: Self
                .canOfferWiderSearch(store) ? { store.send(.searchScopeChanged(.everywhere)) } : nil,
            onRetry: store.searchFailureMessage == nil ? nil : { store.send(.searchRetryTapped) }
        )
    }

    static func isShown(_ store: StoreOf<BrowseFeature>) -> Bool {
        message(store) != nil || canOfferWiderSearch(store)
    }

    private static func message(_ store: StoreOf<BrowseFeature>) -> String? {
        SearchStatusFooter.message(
            failure: store.searchFailureMessage,
            isTooShort: store.isSearchTermTooShort,
            shortfall: store.isSearchingMyFilesAndVolumes && store.searchShortfall != .stoppedEarly
                ? nil
                : store.searchShortfall
        )
    }

    /// A search in a folder can be widened to everywhere, unless the term is too short for the
    /// server to search at all.
    private static func canOfferWiderSearch(_ store: StoreOf<BrowseFeature>) -> Bool {
        store.canWidenSearch && !store.isSearchTermTooShort && store.displayedSearchResults?.isEmpty == false
    }
}

struct BrowseSearchLaneHeader: View {
    let lane: SearchLane

    var body: some View {
        HStack(spacing: .space8) {
            DSFieldLabel(lane.title)
                .accessibilityAddTraits(.isHeader)
            if !lane.rows.isEmpty {
                Text(lane.rows.count.formatted())
                    .type(.body3(.semibold), style: .secondary)
            }
            Spacer(minLength: .space8)
            if let failure = lane.phase.errorMessage {
                Text(failure)
                    .type(.caption(.regular), style: .error)
                    .lineLimit(1)
                if let onRetry = lane.onRetry {
                    Button(L10n.Common.retry, action: onRetry)
                        .type(.body3(.semibold), style: .link)
                        .buttonStyle(.borderless)
                }
            } else if lane.phase == .loading {
                DSSpinner(size: .small)
            } else if let onShowMore = lane.onShowMore {
                Button(L10n.Browse.searchShowMore, action: onShowMore)
                    .type(.body3(.semibold), style: .link)
                    .buttonStyle(.borderless)
            }
        }
    }
}
