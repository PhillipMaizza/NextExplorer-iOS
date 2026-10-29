#if os(iOS)
    import UIKit

    /// The app is portrait-only everywhere except while an image or video viewer is on screen.
    /// `AppDelegate.application(_:supportedInterfaceOrientationsFor:)` reads `mask` on every
    /// rotation attempt; there's no other hook to plumb a per-screen orientation override through
    /// a plain SwiftUI `App`/`WindowGroup`, so this is a deliberate shared mutable singleton
    /// rather than something threaded through the view hierarchy.
    ///
    /// A foldable (iPhone Duo) rotates everywhere instead: its squat outer panel reads well in
    /// landscape and its inner panel ignores the mask anyway. `markFoldable()` flips the default.
    @MainActor
    public final class OrientationLock {
        public static let shared = OrientationLock()

        public private(set) var mask: UIInterfaceOrientationMask = .portrait

        /// Whether a hinge has been reported (iPhone Duo).
        public private(set) var isFoldable = false

        private var defaultMask: UIInterfaceOrientationMask {
            isFoldable ? .allButUpsideDown : .portrait
        }

        private init() {}

        /// Call once a hinge is reported. Idempotent.
        public func markFoldable() {
            guard !isFoldable else { return }
            isFoldable = true
            mask = defaultMask
            requestUpdate()
        }

        /// Call from a media viewer's `.onAppear`.
        public func unlock() {
            mask = .allButUpsideDown
            requestUpdate()
        }

        /// Call from a media viewer's `.onDisappear` — restores the default every other screen
        /// relies on (portrait, or every orientation on a foldable).
        public func lock() {
            mask = defaultMask
            requestUpdate()
        }

        /// `UIViewController.attemptRotationToDeviceOrientation()` (a type method with no notion
        /// of "which screen") was deprecated in iOS 16 in favor of asking the specific visible
        /// view controller to re-check. There's no SwiftUI hook for "the current one," so this
        /// walks the key window's controller chain to find it.
        private func requestUpdate() {
            var controller = ActiveWindowScene.current?.keyWindow?.rootViewController
            while let presented = controller?.presentedViewController {
                controller = presented
            }
            controller?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
#else
    /// macOS windows resize freely, so the lock is a no op there.
    @MainActor
    public final class OrientationLock {
        public static let shared = OrientationLock()

        public let isFoldable = false

        private init() {}

        public func markFoldable() {}

        public func unlock() {}

        public func lock() {}
    }
#endif
