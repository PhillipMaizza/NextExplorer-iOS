import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// What the search on screen has not covered, under its results, as the web client says it:
/// a term too short for the server, a search stopped at its time limit, or a full first page
/// with Show More to widen it.
struct SearchStatusFooter: View {
    let message: String
    let canShowMore: Bool
    let onShowMore: () -> Void

    var body: some View {
        #if os(macOS)
            HStack(spacing: .space8) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: .space8)
                if canShowMore {
                    Button(L10n.Browse.searchShowMore, action: onShowMore)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, .space12)
            .padding(.vertical, .space8)
        #else
            VStack(alignment: .leading, spacing: .space8) {
                Text(message)
                    .type(.body3(.regular), style: .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if canShowMore {
                    Button(L10n.Browse.searchShowMore, action: onShowMore)
                        .type(.body3(.semibold), style: .link)
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, .space16)
            .padding(.vertical, .space12)
        #endif
    }

    /// The footer's text for the search on screen, `nil` when the answer is the whole truth.
    static func message(isTooShort: Bool, shortfall: SearchShortfall?) -> String? {
        if isTooShort {
            return tooShortMessage
        }
        switch shortfall {
        case .stoppedEarly: return L10n.Browse.searchStoppedEarly
        case let .firstOnly(count): return L10n.Browse.searchFirstOnly(count)
        case nil: return nil
        }
    }

    static var tooShortMessage: String {
        L10n.Browse.searchTooShort(FilesClient.minimumSearchTermLength)
    }
}

extension SearchMatchKind {
    var title: String {
        switch self {
        case .name: L10n.Browse.searchMatchedByName
        case .contents: L10n.Browse.searchMatchedByContent
        case .both: L10n.Browse.searchMatchedByBoth
        }
    }
}

#Preview("Too short") {
    SearchStatusFooter(message: SearchStatusFooter.tooShortMessage, canShowMore: false, onShowMore: {})
        .previewCanvasWidth(.sheet)
}

#Preview("First page") {
    SearchStatusFooter(
        message: SearchStatusFooter.message(isTooShort: false, shortfall: .firstOnly(count: 100)) ?? "",
        canShowMore: true,
        onShowMore: {}
    )
    .previewCanvasWidth(.sheet)
}

#Preview("Stopped early") {
    SearchStatusFooter(
        message: SearchStatusFooter.message(isTooShort: false, shortfall: .stoppedEarly) ?? "",
        canShowMore: false,
        onShowMore: {}
    )
    .previewCanvasWidth(.sheet)
}
