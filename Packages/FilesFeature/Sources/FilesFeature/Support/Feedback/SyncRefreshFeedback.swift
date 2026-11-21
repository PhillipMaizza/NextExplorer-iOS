import DesignSystem
import SwiftUI

private struct SyncRefreshFeedback: ViewModifier {
    let errorMessage: String?
    let shouldSignalErrorHaptic: Bool
    let onRefresh: @Sendable () async -> Void
    /// Meaningless value; only the fact that it just changed drives the success haptic.
    @State private var hasFinishedRefreshing = false

    func body(content: Content) -> some View {
        content
            .refreshable {
                await onRefresh()
                hasFinishedRefreshing.toggle()
            }
        #if os(macOS)
            .macToolbarRefresh(onRefresh: onRefresh) { hasFinishedRefreshing.toggle() }
            .syncCompletedToast(hasFinishedRefreshing: hasFinishedRefreshing, isErrorFree: errorMessage == nil)
        #endif
            .hapticFeedback(.success, trigger: hasFinishedRefreshing) { _, _ in errorMessage == nil }
            .hapticFeedback(.error, trigger: errorMessage) { _, newValue in shouldSignalErrorHaptic && newValue != nil }
    }
}

extension View {
    func syncRefreshFeedback(
        errorMessage: String?,
        shouldSignalErrorHaptic: Bool = true,
        onRefresh: @escaping @Sendable () async -> Void
    ) -> some View {
        modifier(SyncRefreshFeedback(
            errorMessage: errorMessage,
            shouldSignalErrorHaptic: shouldSignalErrorHaptic,
            onRefresh: onRefresh
        ))
    }
}

#Preview("Pull to refresh, haptic only") {
    List(0 ..< 5, id: \.self) { Text("Row \($0)") }
        .syncRefreshFeedback(errorMessage: nil) {}
}
