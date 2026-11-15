import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// "Showing a saved copy" notice, rendered as a footer below the last row or cell of the list or
/// grid (not a blocking overlay) whenever the listing on screen came from the offline cache.
struct BrowseOfflineFooter: View {
    let dataSource: BrowseFeature.DataSource
    var isListRow = false

    var body: some View {
        if case let .cached(fetchedAt) = dataSource {
            let text = L10n.Browse.offlineBannerDetail(OfflineRelativeTime.string(from: fetchedAt))
            if isListRow {
                notice(text)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                notice(text)
            }
        }
    }

    private func notice(_ text: String) -> some View {
        #if os(macOS)
            // Under the Mac table: a quiet line in the corner, not a card.
            Label { Text(text) } icon: { IconKit.info }
                .type(.caption(.regular), style: .secondary)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, .space16)
                .padding(.vertical, .space8)
        #else
            DSInfoCard(text)
                .padding(.horizontal, .space16)
                .padding(.top, .space12)
        #endif
    }
}
