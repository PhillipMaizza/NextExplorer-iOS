import DesignSystem
import SwiftUI

/// The pull-to-refresh feedback stack every file listing tab shares (Favorites, Downloads,
/// Shared): run the refresh, then a success/error haptic and the "Sync completed" toast keyed off
/// whether `errorMessage` is nil once it finishes. Owns its own completion trigger, so callers no
/// longer each carry a `didFinishRefreshing` `@State` plus four near-identical modifiers.
private struct SyncRefreshFeedback: ViewModifier {
    let errorMessage: String?
    let signalsErrorHaptic: Bool
    let extraBottomInset: CGFloat
    let onRefresh: @Sendable () async -> Void
    /// Meaningless value; only the fact that it just changed drives the success haptic + toast.
    @State private var didFinishRefreshing = false

    func body(content: Content) -> some View {
        content
            .refreshable {
                await onRefresh()
                didFinishRefreshing.toggle()
            }
            .hapticFeedback(.success, trigger: didFinishRefreshing) { _, _ in errorMessage == nil }
            .hapticFeedback(.error, trigger: errorMessage) { _, newValue in signalsErrorHaptic && newValue != nil }
            .syncCompletedToast(trigger: didFinishRefreshing, isErrorFree: errorMessage == nil, extraBottomInset: extraBottomInset)
    }
}

extension View {
    /// Attach the shared refresh feedback stack. `errorMessage` is the tab's current load/action
    /// error (nil when clear); it drives both the success-vs-error haptic and the toast tone.
    /// `signalsErrorHaptic` is false for tabs that deliberately stay silent on a refresh failure.
    func syncRefreshFeedback(
        errorMessage: String?,
        signalsErrorHaptic: Bool = true,
        extraBottomInset: CGFloat = 0,
        onRefresh: @escaping @Sendable () async -> Void
    ) -> some View {
        modifier(SyncRefreshFeedback(
            errorMessage: errorMessage,
            signalsErrorHaptic: signalsErrorHaptic,
            extraBottomInset: extraBottomInset,
            onRefresh: onRefresh
        ))
    }
}
