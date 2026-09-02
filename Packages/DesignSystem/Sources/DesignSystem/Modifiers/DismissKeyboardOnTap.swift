import SwiftUI
import UIKit

public extension View {
    /// Resigns the first responder (dismisses the keyboard) when the user taps anywhere over
    /// this view — e.g. tapping the empty space of a list while a search field is focused.
    ///
    /// Backed by a window level `UITapGestureRecognizer` with `cancelsTouchesInView = false`
    /// rather than a SwiftUI `simultaneousGesture(TapGesture())`: attaching a tap gesture (even
    /// simultaneous) to a `List` swallows `NavigationLink`/`Button` row activation on iOS and is
    /// unreliable at actually dismissing. A non cancelling window recognizer dismisses on every
    /// tap while leaving the touch untouched for the rows underneath.
    ///
    /// Apply to the scrolling content only, never over the search field itself (that would
    /// defocus it on the same tap that focuses it).
    func dismissKeyboardOnTap() -> some View {
        background(KeyboardDismissTapInstaller())
    }
}

private struct KeyboardDismissTapInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // The view lands in a window a layout pass after creation, so install lazily here and
        // guard against a second recognizer on later updates.
        guard context.coordinator.recognizer == nil, let window = uiView.window else { return }
        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleTap)
        )
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        window.addGestureRecognizer(tap)
        context.coordinator.recognizer = tap
        context.coordinator.window = window
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        if let recognizer = coordinator.recognizer {
            coordinator.window?.removeGestureRecognizer(recognizer)
        }
        coordinator.recognizer = nil
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var recognizer: UITapGestureRecognizer?
        weak var window: UIWindow?

        @objc func handleTap() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }

        // Ignore taps that land on a text input, so tapping a field to focus it doesn't resign
        // the responder on the same tap that begins editing.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView || current is UISearchBar {
                    return false
                }
                view = current.superview
            }
            return true
        }
    }
}
