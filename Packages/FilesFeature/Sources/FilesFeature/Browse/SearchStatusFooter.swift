import CoreModels
import DesignSystem
import FolderPickerFeature
import Localization
import SwiftUI

/// What the search on screen has not covered, under its results, as the web client says it:
/// a term too short for the server, a search stopped at its time limit, or a full first page
/// with Show More to widen it.
struct SearchStatusFooter: View {
    let message: String?
    let canShowMore: Bool
    let onShowMore: () -> Void
    /// Set when the search is inside a folder and can be widened to everywhere.
    var onSearchEverywhere: (() -> Void)?

    var body: some View {
        #if os(macOS)
            HStack(spacing: .space8) {
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: .space8)
                if canShowMore {
                    Button(L10n.Browse.searchShowMore, action: onShowMore)
                        .controlSize(.small)
                }
                if let onSearchEverywhere {
                    Button(L10n.Browse.searchEverywhere, action: onSearchEverywhere)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, .space12)
            .padding(.vertical, .space8)
        #else
            VStack(alignment: .leading, spacing: .space8) {
                if let message {
                    Text(message)
                        .type(.body3(.regular), style: .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if canShowMore {
                    Button(L10n.Browse.searchShowMore, action: onShowMore)
                        .type(.body3(.semibold), style: .link)
                        .buttonStyle(.borderless)
                }
                if let onSearchEverywhere {
                    Button(L10n.Browse.searchEverywhere, action: onSearchEverywhere)
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
        SearchHint.tooShort
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
