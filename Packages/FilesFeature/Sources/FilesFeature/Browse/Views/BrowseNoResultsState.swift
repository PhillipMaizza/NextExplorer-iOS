import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// What a search with no matches shows: a message and, when it helps, a way to search everywhere.
struct BrowseNoResultsState: View {
    let store: StoreOf<BrowseFeature>

    var body: some View {
        #if os(macOS)
            ContentUnavailableView {
                Label { Text(L10n.Browse.searchNoMatchesInFolder(store.searchQuery)) } icon: { IconKit.search }
            } description: {
                if store.isSearchTermTooShort {
                    Text(SearchStatusFooter.tooShortMessage)
                }
            } actions: {
                if store.canWidenSearch, !store.isSearchTermTooShort {
                    Button(L10n.Browse.searchEverywhere) { store.send(.searchScopeChanged(.everywhere)) }
                }
            }
        #else
            iOSBody
        #endif
    }

    private var iOSBody: some View {
        VStack(spacing: Constants.emptyStateSpacing) {
            IconKit.search
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Constants.emptyStateIconSize, height: Constants.emptyStateIconSize)
            Text(L10n.Browse.searchNoMatchesInFolder(store.searchQuery))
                .type(.body1(.semibold), style: .secondary)
            if store.isSearchTermTooShort {
                Text(SearchStatusFooter.tooShortMessage)
                    .type(.body3(.regular), style: .secondary)
                    .multilineTextAlignment(.center)
            } else if store.canWidenSearch {
                DSButton(
                    L10n.Browse.searchEverywhere,
                    icon: IconKit.search,
                    style: .secondary,
                    size: .small,
                    isLoading: false,
                    action: {
                        store.send(.searchScopeChanged(.everywhere))
                    }
                )
                .padding(.top, Constants.emptyStateSpacing)
            }
        }
        .padding(.space16)
        .multilineTextAlignment(.center)
    }
}

private enum Constants {
    static let emptyStateSpacing: CGFloat = .space8
    static let emptyStateIconSize: CGFloat = .superIcon
}
