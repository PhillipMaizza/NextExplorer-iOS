import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI

/// Favorites' recursive file search results, in place of the favorites list while a term the
/// server searches is typed: skeleton rows until the first answer, then the hits. Tapping a hit
/// opens it; a long press can show the folder it lives in.
struct FavoritesSearchResultsList: View {
    let store: StoreOf<FavoritesFeature>
    /// The screen's state: skeleton rows while `.loading`, list diffs animated only in `.content`.
    let phase: ListPhase
    @Binding var pullOffset: CGFloat

    var body: some View {
        let results = store.displayedSearchResults
        let firstID = results.first?.id
        let lastID = results.last?.id
        DSGroupedList {
            if phase == .loading {
                SkeletonFileRows(entries: FavoritesSkeleton.entries)
            } else {
                ForEach(results) { result in
                    DSFlashingListRow {
                        Button {
                            store.send(.searchResultTapped(result))
                        } label: {
                            SearchResultRow(result: result)
                        }
                        .buttonStyle(DSHapticButtonStyle())
                        .contextMenu {
                            SearchResultMenu(
                                result: result,
                                onOpen: { store.send(.searchResultTapped(result)) },
                                onShowInFolder: { store.send(.searchResultEnclosingFolderTapped(result)) }
                            )
                        }
                        .listRowSeparator(result.id == firstID ? .hidden : .visible, edges: .top)
                        .listRowSeparator(result.id == lastID ? .hidden : .visible, edges: .bottom)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .backgroundGradient()
        .scrollPullOffset($pullOffset)
        .dismissKeyboardOnTap()
        .animation(phase == .content ? DSMotion.listDiff : nil, value: store.fileSearchResults)
    }
}

/// The favorites tab's placeholders: folders, uneven widths.
enum FavoritesSkeleton {
    static let entries = [6, 12, 4, 9, 15, 7, 11, 5, 13, 8].map { SkeletonEntry(name: SkeletonEntry.text($0), isDirectory: true) }
}

@MainActor
private func previewStore(results: [SearchResultItem]?, phase: DataPhase) -> StoreOf<FavoritesFeature> {
    var state = FavoritesFeature.State(serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"))
    state.searchQuery = "budget"
    state.fileSearchResults = results.map { IdentifiedArray(uniqueElements: $0) }
    state.searchPhase = phase
    return Store(initialState: state) { EmptyReducer() }
}

#Preview("Loading") {
    FavoritesSearchResultsList(store: previewStore(results: nil, phase: .loading), phase: .loading, pullOffset: .constant(0))
}

#Preview("Results") {
    FavoritesSearchResultsList(
        store: previewStore(results: [
            SearchResultItem(name: "budget.xlsx", path: "Documents", kind: "file", isNameMatch: true),
            SearchResultItem(name: "notes.md", path: "Documents", kind: "file", matchLine: "budget for the trip", matchLineNumber: 12, isContentMatch: true),
        ], phase: .loaded),
        phase: .content,
        pullOffset: .constant(0)
    )
}
