import DesignSystem
import Localization
import SwiftUI

/// The single screen state a scrollable list is in. The view computes one of these from its
/// store; `ListStatePlaceholder` renders the message for `.error` / `.empty` / `.noResults`
/// and nothing for `.loading` (a per-tab skeleton covers that) or `.content` (the list shows
/// through). Browse, Favorites, Downloads and Shared all map to the same set.
enum ListPhase: Equatable {
    case loading, error, empty, noResults, content

    /// The non content, non loading states that show a placeholder instead of rows.
    var isPlaceholder: Bool {
        self == .error || self == .empty || self == .noResults
    }

    /// The one screen-state precedence every listing tab shares: a first-load error wins, then
    /// the skeleton until the first response lands, then the empty state, then a search that
    /// matched nothing, else the list. Callers pass the four predicates their store derives, so
    /// the ordering lives here once instead of being re-spelled (and drifting) per view. A tab
    /// with a bespoke branch (e.g. Favorites' search-results mode) computes that itself and
    /// falls back to this for the ordinary path.
    static func derive(hasError: Bool, hasLoaded: Bool, isEmpty: Bool, hasNoResults: Bool) -> ListPhase {
        if hasError {
            return .error
        }
        if !hasLoaded, isEmpty {
            return .loading
        }
        if isEmpty {
            return .empty
        }
        if hasNoResults {
            return .noResults
        }
        return .content
    }
}

/// The centred message for a list's `.error` / `.empty` / `.noResults` states. Rendered as an
/// `.overlay` on the list, but fed the list's live pull-to-refresh drag (`pullOffset`) so it
/// translates with the rubber-band instead of staying pinned while the list stretches under
/// it. Each message stays mounted at zero opacity: a phase flip that lands mid-layout can't
/// then drag one in from a corner. The caller owns the cross-fade
/// (`.animation(_:value: listPhase)` around the `Group { list }.overlay { … }`).
struct ListStateOverlay: View {
    let phase: ListPhase
    let errorMessage: String?
    let emptyIcon: Image
    let emptyMessage: String
    let noResultsMessage: String
    var pullOffset: CGFloat = 0
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            // Each state stays mounted so the swap crossfades; a hidden one is also hidden from
            // VoiceOver, which otherwise reads every message over the loaded list.
            EmptyStateView(
                icon: IconKit.warning,
                message: errorMessage ?? "",
                retry: onRetry
            )
            .shown(phase == .error && errorMessage != nil)

            EmptyStateView(icon: emptyIcon, message: emptyMessage)
                .shown(phase == .empty)

            EmptyStateView(icon: IconKit.search, message: noResultsMessage)
                .shown(phase == .noResults)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: pullOffset)
        // Let list-row taps through whenever the list itself is on screen; capture them (and
        // keep the retry button live) only while a placeholder is up.
        .allowsHitTesting(phase.isPlaceholder)
    }
}

private extension View {
    func shown(_ isShown: Bool) -> some View {
        opacity(isShown ? 1 : 0)
            .accessibilityHidden(!isShown)
    }
}

/// Tracks how far a scroll view has been pulled below its resting offset (0 at rest or when
/// scrolled up), for feeding an `.overlay` that should follow a pull-to-refresh rubber-band.
/// Keyed off `contentOffset + contentInset`, which is 0 at rest regardless of how far the
/// large title has collapsed and only goes negative on an over-pull.
struct ScrollPullOffset: ViewModifier {
    @Binding var pull: CGFloat

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self) {
            $0.contentOffset.y + $0.contentInsets.top
        } action: { _, overscroll in
            pull = max(0, -overscroll)
        }
    }
}

extension View {
    func scrollPullOffset(_ pull: Binding<CGFloat>) -> some View {
        modifier(ScrollPullOffset(pull: pull))
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
