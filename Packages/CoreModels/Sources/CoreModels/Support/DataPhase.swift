import Foundation

/// A list feature's data loading lifecycle, held in the reducer `State` in place of a spread
/// of `isLoading` / `hasLoaded` / `errorMessage` bools. The view maps this: together with
/// whether the data is empty and whether a search is active: onto a `ListPhase`.
public enum DataPhase: Equatable, Sendable {
    /// Never loaded. The only state `onAppear` kicks a fetch from.
    case idle
    /// First load in flight, nothing to show yet.
    case loading
    /// At least one load has landed (the data itself may still be empty).
    case loaded
    /// The first load failed with nothing to fall back to.
    case failed(String)

    /// True once any load has resolved: a later failure over already loaded data stays
    /// `.loaded` and toasts instead, so this only goes back to false on an explicit reload.
    public var hasLoaded: Bool {
        switch self {
        case .idle, .loading: false
        case .loaded, .failed: true
        }
    }

    /// The full screen error text, set only while the first load is `.failed`.
    public var errorMessage: String? {
        if case let .failed(message) = self {
            return message
        }
        return nil
    }

    /// Whether an `onAppear` (or a return to this segment/tab) should kick a load: yes when
    /// nothing has loaded yet or the last attempt failed, no while one is in flight or a
    /// success is already on screen (that's what stops an empty result refetching every
    /// single time the tab is revisited).
    public var shouldLoadOnAppear: Bool {
        switch self {
        case .idle, .failed: true
        case .loading, .loaded: false
        }
    }
}
