import DesignSystem
import SwiftUI

/// The pull to refresh feedback every file listing tab shares (Favorites, Downloads, Shared): run
/// the refresh, then a success or error haptic keyed off whether `errorMessage` is nil once it
/// finishes. No toast on iOS: the haptic and the refreshed list are the confirmation; the Mac, which
/// has no haptics, keeps its "Sync completed" toast. Owns its own completion trigger, so callers
/// don't each carry a `didFinishRefreshing` `@State`.
private struct SyncRefreshFeedback: ViewModifier {
    let errorMessage: String?
    let signalsErrorHaptic: Bool
    let onRefresh: @Sendable () async -> Void
    /// Meaningless value; only the fact that it just changed drives the success haptic.
    @State private var didFinishRefreshing = false

    func body(content: Content) -> some View {
        content
            .refreshable {
                await onRefresh()
                didFinishRefreshing.toggle()
            }
        #if os(macOS)
            .macToolbarRefresh(onRefresh: onRefresh) { didFinishRefreshing.toggle() }
            .syncCompletedToast(trigger: didFinishRefreshing, isErrorFree: errorMessage == nil)
        #endif
            .hapticFeedback(.success, trigger: didFinishRefreshing) { _, _ in errorMessage == nil }
            .hapticFeedback(.error, trigger: errorMessage) { _, newValue in signalsErrorHaptic && newValue != nil }
    }
}

extension View {
    /// Attach the shared refresh feedback. `errorMessage` is the tab's current load or action error
    /// (nil when clear); it picks the success or error haptic. `signalsErrorHaptic` is false for
    /// tabs that deliberately stay silent on a refresh failure.
    func syncRefreshFeedback(
        errorMessage: String?,
        signalsErrorHaptic: Bool = true,
        onRefresh: @escaping @Sendable () async -> Void
    ) -> some View {
        modifier(SyncRefreshFeedback(
            errorMessage: errorMessage,
            signalsErrorHaptic: signalsErrorHaptic,
            onRefresh: onRefresh
        ))
    }
}

#Preview("Pull to refresh, haptic only") {
    List(0 ..< 5, id: \.self) { Text("Row \($0)") }
        .syncRefreshFeedback(errorMessage: nil) {}
}
