import SwiftUI
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// Shared animation tokens for list screens, so Browse / Favorites / Downloads / Shared
/// cross-fade and reorder identically instead of each carrying its own copy of the numbers.
public enum DSMotion {
    /// Skeleton → content (and any list-state) cross-fade.
    public static let contentRevealDuration: Double = 0.3

    /// The cross-fade animation itself.
    public static var contentReveal: Animation {
        .easeInOut(duration: contentRevealDuration)
    }

    /// Row insert / remove / reorder inside a settled list.
    public static var listDiff: Animation {
        .spring(response: 0.35, dampingFraction: 0.8)
    }

    /// A disclosure row expanding / collapsing (chevron rotation + body reveal).
    public static var disclosure: Animation {
        .spring(response: 0.3, dampingFraction: 0.78)
    }

    /// A list changing shape on request (select mode in or out, a new sort order): `listDiff`, or
    /// a short crossfade when Reduce Motion is on, so the change still shows without the movement.
    @MainActor
    public static var listChange: Animation {
        isReduceMotionEnabled ? contentReveal : listDiff
    }

    /// How long one select mode step takes to settle with `selectModeStep`.
    public static let selectModeStepDuration: Duration = .milliseconds(250)

    /// How long a toolbar menu takes to close back into its button.
    public static let menuCloseDuration: Duration = .milliseconds(250)

    /// How fast animations run: 1 normally. UI tests raise it so animations finish almost at once,
    /// or lower it to record them, together with the window's layer speed.
    @MainActor
    public static var speed: Double = 1

    /// Waits out one animation step at `speed`, so steps that run one after another keep pace with
    /// their animations under a UI test too.
    @MainActor
    public static func waitForStep(_ duration: Duration) async throws {
        try await Task.sleep(for: duration * (1 / speed))
    }

    /// Each step of entering or leaving select mode (the tab bar, the selection circles): one
    /// quicker spring for every step so the sequence reads as one, or a crossfade under Reduce Motion.
    @MainActor
    public static var selectModeStep: Animation {
        isReduceMotionEnabled ? contentReveal : .spring(response: 0.25, dampingFraction: 0.85)
    }

    /// How long the gallery's fades take.
    public static let galleryFadeDuration: Double = 0.22

    /// Every fade in the gallery (its bars on a tap, a photo replacing its placeholder and settling,
    /// the PDF page pill): one curve, so the pages and the chrome move alike.
    public static var galleryFade: Animation {
        .easeInOut(duration: galleryFadeDuration)
    }

    @MainActor
    private static var isReduceMotionEnabled: Bool {
        #if os(iOS)
            UIAccessibility.isReduceMotionEnabled
        #elseif os(macOS)
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #endif
    }
}
