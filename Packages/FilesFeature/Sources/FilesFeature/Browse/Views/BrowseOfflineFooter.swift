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
    var onServerProblemRetry: (() -> Void)?

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

    @ViewBuilder
    private func notice(_ text: String) -> some View {
        #if os(macOS)
            if let onServerProblemRetry {
                serverProblemNotice(text, onRetry: onServerProblemRetry)
            } else {
                savedCopyNotice(text)
            }
        #else
            DSInfoCard(text)
                .padding(.horizontal, .space16)
                .padding(.top, .space12)
        #endif
    }

    #if os(macOS)
        private func serverProblemNotice(_ text: String, onRetry: @escaping () -> Void) -> some View {
            HStack(spacing: .space8) {
                IconKit.macWarning
                    .resizable()
                    .scaledToFit()
                    .frame(width: .size16, height: .size16)
                    .foregroundStyle(Color.accentText)
                    .accessibilityHidden(true)
                Text(L10n.Browse.serverProblemFooter)
                    .type(.body3(.semibold))
                Text(text)
                    .type(.body3(.regular), style: .secondary)
                Spacer(minLength: .space8)
                Button(L10n.Common.retry, action: onRetry)
                    .buttonStyle(.macDS(.secondary, size: .small))
            }
            .padding(.horizontal, .space16)
            .padding(.vertical, .space8)
        }

        private func savedCopyNotice(_ text: String) -> some View {
            Label { Text(text) } icon: { IconKit.info }
                .type(.caption(.regular), style: .secondary)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, .space16)
                .padding(.vertical, .space8)
        }
    #endif
}

#Preview("Saved copy") {
    BrowseOfflineFooter(dataSource: .cached(fetchedAt: .now.addingTimeInterval(-3600)))
}

#Preview("Server problem") {
    BrowseOfflineFooter(dataSource: .cached(fetchedAt: .now.addingTimeInterval(-3600)), onServerProblemRetry: {})
}

#Preview("Live") {
    BrowseOfflineFooter(dataSource: .live)
}
