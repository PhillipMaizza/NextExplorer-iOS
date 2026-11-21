import ComposableArchitecture
import DesignSystem
import SwiftUI

/// Sign in buttons wait for a keyboard to finish dismissing before they act: the dismiss
/// reflow and the button's collapse morph fighting over the same frames swallow the spinner.
enum LoginKeyboard {
    /// UIKit's own keyboard dismiss duration.
    private static let dismissDuration: Duration = .seconds(0.25)

    /// A Mac has no on screen keyboard, so there is no dismiss to wait out.
    private static var isSoftware: Bool {
        #if os(iOS)
            true
        #else
            false
        #endif
    }

    /// Sends `action` now, or once the keyboard is down when a field had focus.
    @MainActor
    static func send(
        _ action: LoginFormFeature.Action,
        to store: StoreOf<LoginFormFeature>,
        afterDismissing wasFocused: Bool
    ) {
        guard isSoftware, wasFocused else {
            store.send(action)
            return
        }
        Task {
            try? await DSMotion.waitForStep(dismissDuration)
            guard !Task.isCancelled else { return }
            store.send(action)
        }
    }
}
