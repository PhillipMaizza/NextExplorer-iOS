import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// What a trash screen shows around its list: a spinner while nothing is listed yet, the failure with
/// Retry, the screen's own empty state, or the list. A reload keeps the list on screen.
struct TrashPhaseContent<Empty: View, Loaded: View>: View {
    let phase: DataPhase
    let isEmpty: Bool
    let onRetry: () -> Void
    @ViewBuilder let empty: () -> Empty
    @ViewBuilder let loaded: () -> Loaded

    var body: some View {
        if isEmpty {
            switch phase {
            case .idle, .loading:
                DSSpinner()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                EmptyStateView(icon: IconKit.warning, message: message, retry: onRetry)
            case .loaded:
                empty()
            }
        } else {
            loaded()
        }
    }
}

#Preview("Loading") {
    TrashPhaseContent(phase: .loading, isEmpty: true, onRetry: {}) { EmptyView() } loaded: { EmptyView() }
}

#Preview("Failed") {
    TrashPhaseContent(phase: .failed(L10n.Trash.loadFailed), isEmpty: true, onRetry: {}) { EmptyView() } loaded: {
        EmptyView()
    }
}

#Preview("Empty, dark") {
    TrashPhaseContent(phase: .loaded, isEmpty: true, onRetry: {}) {
        EmptyStateView(icon: IconKit.delete, message: L10n.Trash.emptyState)
    } loaded: {
        EmptyView()
    }
    .preferredColorScheme(.dark)
}
