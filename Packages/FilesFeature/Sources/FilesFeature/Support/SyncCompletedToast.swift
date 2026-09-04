import DesignSystem
import Localization
import SwiftUI

/// Raises a "Sync completed" toast each time a pull to refresh finishes without error. The
/// list screens already flip a `didFinishRefreshing` toggle after their refresh effect
/// resolves (and drive a success haptic off it); this hangs the confirmation toast on the
/// same signal so every tab confirms a manual refresh the same way.
private struct SyncCompletedToast: ViewModifier {
    let trigger: Bool
    let isErrorFree: Bool
    let extraBottomInset: CGFloat

    @State private var toast: DSToastMessage?

    func body(content: Content) -> some View {
        content
            .dsToast($toast, extraBottomInset: extraBottomInset)
            .onChange(of: trigger) { _, _ in
                guard isErrorFree else { return }
                toast = .success(L10n.Common.syncCompleted)
            }
    }
}

extension View {
    /// - Parameters:
    ///   - trigger: the view's `didFinishRefreshing` toggle, flipped once a refresh resolves.
    ///   - isErrorFree: whether the just-finished refresh left the list without an error.
    func syncCompletedToast(trigger: Bool, isErrorFree: Bool, extraBottomInset: CGFloat = 0) -> some View {
        modifier(SyncCompletedToast(trigger: trigger, isErrorFree: isErrorFree, extraBottomInset: extraBottomInset))
    }
}
