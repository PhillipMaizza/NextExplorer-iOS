import UIKit

/// The app is portrait-only everywhere except while an image or video viewer is on screen.
/// `AppDelegate.application(_:supportedInterfaceOrientationsFor:)` reads `mask` on every
/// rotation attempt; there's no other hook to plumb a per-screen orientation override through
/// a plain SwiftUI `App`/`WindowGroup`, so this is a deliberate shared mutable singleton
/// rather than something threaded through the view hierarchy.
@MainActor
public final class OrientationLock {
    public static let shared = OrientationLock()

    public private(set) var mask: UIInterfaceOrientationMask = .portrait

    private init() {}

    /// Call from a media viewer's `.onAppear`.
    public func unlock() {
        mask = .allButUpsideDown
        requestUpdate()
    }

    /// Call from a media viewer's `.onDisappear` — restores the portrait-only default every
    /// other screen relies on.
    public func lock() {
        mask = .portrait
        requestUpdate()
    }

    /// `UIViewController.attemptRotationToDeviceOrientation()` (a type method with no notion
    /// of "which screen") was deprecated in iOS 16 in favor of asking the specific visible
    /// view controller to re-check. There's no SwiftUI hook for "the current one," so this
    /// walks the key window's controller chain to find it.
    private func requestUpdate() {
        var controller = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        controller?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
