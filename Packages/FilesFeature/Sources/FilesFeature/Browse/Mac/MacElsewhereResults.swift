#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    struct MacElsewhereResults<FileActions: View>: View {
        let store: StoreOf<BrowseFeature>
        @Environment(\.macTextScale) var macTextScale
        @ViewBuilder let fileActions: (SearchResultItem) -> FileActions

        var body: some View {
            VStack(spacing: 0) {
                MacSearchResultsTable(
                    sections: SearchResultSections([], onDeviceIDs: []),
                    elsewhere: store.elsewhereResults,
                    elsewhereNote: note,
                    favoritePaths: store.favoritePaths,
                    serverURL: store.preferences.shouldShowThumbnails ? store.serverURL : nil,
                    onOpen: { store.send(.searchResultTapped($0)) },
                    fileActions: fileActions
                )
                HStack {
                    Spacer(minLength: .space8)
                    Button(L10n.Search.showAllEverywhere) { store.send(.searchScopeChanged(.everywhere)) }
                        .buttonStyle(.macDS(.secondary, size: .small))
                }
                .padding(.horizontal, .space12)
                .padding(.vertical, .space8)
            }
            .backgroundGradient()
        }

        private var note: AttributedString {
            let term = SearchTerm(store.searchQuery).text
            var note = AttributedString(L10n.Search.nothingInThisFolder(term))
            if let range = note.range(of: term) {
                note[range].foregroundColor = Color.primaryDS
                note[range].font = Typography.TextType.body3(.bold).font(scale: macTextScale).weight(.bold)
            }
            return note
        }
    }

    struct MacElsewhereSectionHeader: View {
        let note: AttributedString?
        let count: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if let note {
                    Text(note)
                        .type(.body3(.regular), style: .secondary)
                        .lineLimit(2)
                        .padding(.vertical, .space12)
                    Divider()
                }
                HStack(spacing: .space8) {
                    Text(L10n.Search.inOtherFolders)
                        .type(.body3(.bold), style: .primaryOnSurface)
                    Spacer(minLength: .space8)
                    Text(count.formatted())
                        .type(.body3(.semibold), style: .secondary)
                }
                .padding(.top, .space12)
                .padding(.bottom, .space4)
            }
        }
    }

    #Preview("In other folders") {
        let state = BrowseFeature.State.preview { state in
            state.searchQuery = "readme"
            state.elsewherePhase = .loaded
            state.elsewhereResults = [
                SearchResultItem(name: "readme.txt", path: "Files/05 Text and Code", kind: "file", isNameMatch: true),
                SearchResultItem(name: "readme.txt", path: "Files/qa-bundle", kind: "file", isNameMatch: true),
            ]
        }
        MacElsewhereResults(store: Store(initialState: state) { BrowseFeature() }) { _ in EmptyView() }
            .previewCanvas(.table)
    }
#endif
