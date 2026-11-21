import DesignSystem
import Localization
import SwiftUI

/// Raises a "Sync completed" toast each time a refresh finishes without error. Mac only: it has no
/// haptics, so the toast is the confirmation of a toolbar or ⌘R refresh. iOS confirms with the
/// success haptic alone.
private struct SyncCompletedToast: ViewModifier {
    let hasFinishedRefreshing: Bool
    let isErrorFree: Bool
    let extraBottomInset: CGFloat

    @State private var toast: DSToastMessage?

    func body(content: Content) -> some View {
        content
            .dsToast($toast, extraBottomInset: extraBottomInset)
            .onChange(of: hasFinishedRefreshing) { _, _ in
                guard isErrorFree else { return }
                toast = .success(L10n.Common.syncCompleted)
            }
    }
}

extension View {
    /// `hasFinishedRefreshing` is the view's toggle, flipped once a refresh resolves; `isErrorFree`
    /// says the refresh left the list without an error.
    func syncCompletedToast(
        hasFinishedRefreshing: Bool,
        isErrorFree: Bool,
        extraBottomInset: CGFloat = 0
    ) -> some View {
        modifier(SyncCompletedToast(
            hasFinishedRefreshing: hasFinishedRefreshing,
            isErrorFree: isErrorFree,
            extraBottomInset: extraBottomInset
        ))
    }
}
