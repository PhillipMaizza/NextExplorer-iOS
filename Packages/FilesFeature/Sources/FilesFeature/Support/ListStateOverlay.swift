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
}

/// A list feature's data-loading lifecycle, held in the reducer `State` in place of a spread
/// of `isLoading` / `hasLoaded` / `errorMessage` bools. The view maps this — together with
/// whether the data is empty and whether a search is active — onto a `ListPhase`.
public enum DataPhase: Equatable, Sendable {
    /// Never loaded. The only state `onAppear` kicks a fetch from.
    case idle
    /// First load in flight, nothing to show yet.
    case loading
    /// At least one load has landed (the data itself may still be empty).
    case loaded
    /// The first load failed with nothing to fall back to.
    case failed(String)

    /// True once any load has resolved — a later failure over already loaded data stays
    /// `.loaded` and toasts instead, so this only goes back to false on an explicit reload.
    public var hasLoaded: Bool {
        switch self {
        case .idle, .loading: false
        case .loaded, .failed: true
        }
    }

    /// The full screen error text, set only while the first load is `.failed`.
    public var errorMessage: String? {
        if case let .failed(message) = self { return message }
        return nil
    }

    /// Whether an `onAppear` (or a return to this segment/tab) should kick a load: yes when
    /// nothing has loaded yet or the last attempt failed, no while one is in flight or a
    /// success is already on screen (that's what stops an empty result refetching every
    /// single time the tab is revisited).
    public var shouldLoadOnAppear: Bool {
        switch self {
        case .idle, .failed: return true
        case .loading, .loaded: return false
        }
    }
}

/// The centred message for a list's `.error` / `.empty` / `.noResults` states. Rendered as an
/// `.overlay` on the list, but fed the list's live pull-to-refresh drag (`pullOffset`) so it
/// translates with the rubber-band instead of staying pinned while the list stretches under
/// it. Each message stays mounted at zero opacity — a phase flip that lands mid-layout can't
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
            EmptyStateView(icon: IconKit.warning, message: errorMessage ?? "", retry: onRetry)
                .opacity(phase == .error && errorMessage != nil ? 1 : 0)

            EmptyStateView(icon: emptyIcon, message: emptyMessage)
                .opacity(phase == .empty ? 1 : 0)

            EmptyStateView(icon: IconKit.search, message: noResultsMessage)
                .opacity(phase == .noResults ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: pullOffset)
        // Let list-row taps through whenever the list itself is on screen; capture them (and
        // keep the retry button live) only while a placeholder is up.
        .allowsHitTesting(phase.isPlaceholder)
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
