import ComposableArchitecture
import CoreModels
import DesignSystem
import Foundation
import SwiftUI

/// The type chips under the browse header: over search results while searching, over the
/// folder's own items otherwise (shown but locked while picking, so the picks stay what is on
/// screen and an active filter stays visible), and nothing when there is only one kind to show.
struct BrowseFilterChipRow: View {
    let store: StoreOf<BrowseFeature>

    var body: some View {
        if store.isSearching, !store.availableSearchCategories.isEmpty {
            SearchFilterChips(
                availableCategories: store.availableSearchCategories,
                selectedCategories: store.selectedSearchCategories,
                onToggle: { store.send(.searchCategoryToggled($0), animation: DSMotion.listDiff) },
                onSelectAll: { store.send(.searchFilterCleared, animation: DSMotion.listDiff) }
            )
        } else if !store.isSearching, !store.availableFolderCategories.isEmpty {
            SearchFilterChips(
                availableCategories: store.availableFolderCategories,
                selectedCategories: store.selectedFolderCategories,
                onToggle: { store.send(.folderCategoryToggled($0), animation: DSMotion.listDiff) },
                onSelectAll: { store.send(.folderFilterCleared, animation: DSMotion.listDiff) }
            )
            .disabled(store.isSelecting)
        }
    }
}

@MainActor
private func previewStore(kinds: [String], picked: Set<FileCategory> = []) -> StoreOf<BrowseFeature> {
    var state = BrowseFeature.State(
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        directoryPath: "",
        title: "Files"
    )
    state.items = IdentifiedArray(uniqueElements: kinds.enumerated().map { index, kind in
        FileItem(name: "item\(index).\(kind)", path: "", dateModified: Date(), size: 1, kind: kind)
    })
    state.selectedFolderCategories = picked
    return Store(initialState: state) { BrowseFeature() }
}

#Preview("Folder with several kinds") {
    BrowseFilterChipRow(store: previewStore(kinds: ["jpg", "pdf", "mp4"]))
        .padding(.space16)
}

#Preview("A kind picked, dark") {
    BrowseFilterChipRow(store: previewStore(kinds: ["jpg", "pdf", "mp4"], picked: [.image]))
        .padding(.space16)
        .preferredColorScheme(.dark)
}

#Preview("One kind offers nothing") {
    BrowseFilterChipRow(store: previewStore(kinds: ["pdf", "pdf"]))
        .padding(.space16)
}
