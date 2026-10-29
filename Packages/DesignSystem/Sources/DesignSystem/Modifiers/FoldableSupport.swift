import SwiftUI
#if os(iOS)
    import UIKit
#endif

// iPhone Duo APIs ship in the iOS 27.1 SDK (SwiftUI 8.0.85, UIKit 9127.0.85). Older SDKs, CI
// included, compile these modifiers as pass throughs.

public extension View {
    /// Switches `OrientationLock` to its foldable default once the system reports a hinge.
    /// Apply once, at the app root.
    func observesFoldableHinge() -> some View {
        modifier(FoldableHingeObserver())
    }

    /// On iPhone Duo the tab bar and a screen's toolbar items share one vertical bar, and the
    /// system compresses the toolbar items first, hiding actions like select or add behind a
    /// zero sized wrapper. Asks it to collapse the tab bar to the current tab instead.
    /// Apply to the screen INSIDE its `NavigationStack`, so the pushed controller is found.
    func prefersToolbarItemsInVerticalBar() -> some View {
        modifier(VerticalBarItemsPreference())
    }
}

private struct FoldableHingeObserver: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS) && canImport(SwiftUI, _version: 8.0.85)
            if #available(iOS 27.1, *) {
                content.onHingeChange { _, context in
                    if context.hinge != nil {
                        OrientationLock.shared.markFoldable()
                    }
                }
            } else {
                content
            }
        #else
            content
        #endif
    }
}

private struct VerticalBarItemsPreference: ViewModifier {
    func body(content: Content) -> some View {
        #if canImport(UIKit, _version: 9127.0.85)
            if #available(iOS 27.1, *) {
                content.background(VerticalBarProbe().accessibilityHidden(true))
            } else {
                content
            }
        #else
            content
        #endif
    }
}

#if canImport(UIKit, _version: 9127.0.85)
    /// A hidden child controller that walks up to the controller the `UINavigationController`
    /// pushed (the screen's hosting controller) and sets the compression behavior on its
    /// `navigationItem`. SwiftUI has no modifier for it.
    @available(iOS 27.1, *)
    private struct VerticalBarProbe: UIViewControllerRepresentable {
        func makeUIViewController(context _: Context) -> ProbeController {
            ProbeController()
        }

        func updateUIViewController(_ controller: ProbeController, context _: Context) {
            controller.apply()
        }

        final class ProbeController: UIViewController {
            override func loadView() {
                view = UIView()
                view.isHidden = true
                view.isUserInteractionEnabled = false
            }

            override func didMove(toParent parent: UIViewController?) {
                super.didMove(toParent: parent)
                apply()
            }

            override func viewWillAppear(_ animated: Bool) {
                super.viewWillAppear(animated)
                apply()
            }

            func apply() {
                var controller: UIViewController? = self
                while let current = controller, !(current.parent is UINavigationController) {
                    controller = current.parent
                }
                controller?.navigationItem.verticalBarCompressionBehavior = .prefersBarItems
            }
        }
    }
#endif
