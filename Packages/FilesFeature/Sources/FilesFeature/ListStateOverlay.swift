import DesignSystem
import Localization
import SwiftUI

/// The cross-fading overlay shown over a scrollable list for its non-content states: first
/// load, load failure, empty, and "search matched nothing". Browse, Favorites, Downloads and
/// Shared all layer the same four states over their list the same way; each passes its own
/// icon/copy and maps its store to a `Phase`.
///
/// The caller owns the crossfade animation, e.g.
/// `.overlay { ListStateOverlay(...) }.animation(.easeInOut(duration: ...), value: phase)`.
struct ListStateOverlay: View {
    enum Phase: Hashable {
        case none, loading, error, empty, noResults
    }

    let phase: Phase
    let errorMessage: String?
    let emptyIcon: Image
    let emptyMessage: String
    let noResultsMessage: String
    let onRetry: () -> Void

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
                    .transition(.opacity)
            case .error:
                if let errorMessage {
                    EmptyStateView(icon: IconKit.warning, message: errorMessage, retry: onRetry)
                        .transition(.opacity)
                }
            case .empty:
                EmptyStateView(icon: emptyIcon, message: emptyMessage)
                    .transition(.opacity)
            case .noResults:
                EmptyStateView(icon: IconKit.search, message: noResultsMessage)
                    .transition(.opacity)
            case .none:
                EmptyView()
            }
        }
        .id(phase)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Loading") {
    Color.backgroundPrimary.overlay {
        ListStateOverlay(phase: .loading, errorMessage: nil, emptyIcon: IconKit.star, emptyMessage: "", noResultsMessage: "", onRetry: {})
    }
}

#Preview("Error") {
    Color.backgroundPrimary.overlay {
        ListStateOverlay(
            phase: .error, errorMessage: "Couldn't reach the server.",
            emptyIcon: IconKit.star, emptyMessage: "", noResultsMessage: "", onRetry: {}
        )
    }
}

#Preview("Empty") {
    Color.backgroundPrimary.overlay {
        ListStateOverlay(
            phase: .empty, errorMessage: nil,
            emptyIcon: IconKit.star, emptyMessage: "Star folders in Browse to see them here.",
            noResultsMessage: "", onRetry: {}
        )
    }
}
