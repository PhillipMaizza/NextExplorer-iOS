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
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = InstallerView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_: UIView, context _: Context) {}

    static func dismantleUIView(_: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Installs the recognizer from `didMoveToWindow` rather than `updateUIView`: the window is
    /// guaranteed present exactly when this fires, whereas `updateUIView` is not guaranteed to run
    /// again after the view first lands in a window — if it didn't, the recognizer was never
    /// installed and tap to dismiss silently did nothing. Also re-attaches if the view moves to a
    /// different window and detaches when it leaves one.
    final class InstallerView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var recognizer: UITapGestureRecognizer?
        private weak var window: UIWindow?

        func attach(to newWindow: UIWindow?) {
            guard let newWindow else { detach(); return }
            if window === newWindow, recognizer != nil {
                return
            }
            detach()
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            newWindow.addGestureRecognizer(tap)
            recognizer = tap
            window = newWindow
        }

        func detach() {
            if let recognizer, let window {
                window.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            window = nil
        }

        @objc func handleTap() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }

        /// Ignore taps that land on a text input, so tapping a field to focus it doesn't resign
        /// the responder on the same tap that begins editing.
        func gestureRecognizer(
            _: UIGestureRecognizer,
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
