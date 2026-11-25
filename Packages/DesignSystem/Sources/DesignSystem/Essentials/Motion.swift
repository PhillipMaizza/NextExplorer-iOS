import SwiftUI
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// Shared animation tokens for list screens, so Browse / Favorites / Downloads / Shared
/// cross fade and reorder identically instead of each carrying its own copy of the numbers.
public enum DSMotion {
    /// Skeleton → content (and any list state) cross fade.
    public static let contentRevealDuration: Double = 0.3

    /// The cross fade animation itself.
    public static var contentReveal: Animation {
        .easeInOut(duration: contentRevealDuration)
    }

    /// Row insert / remove / reorder inside a settled list.
    public static var listDiff: Animation {
        .spring(response: 0.35, dampingFraction: 0.8)
    }

    /// How long `quickFade` takes.
    public static let quickFadeDuration: Double = 0.15

    /// Small state on a control: a field's focus, a validation line, a value swapping in a field or a
    /// button, a press settling.
    public static var quickFade: Animation {
        .easeInOut(duration: quickFadeDuration)
    }

    /// How long `stateFade` takes.
    public static let stateFadeDuration: Double = 0.2

    /// A state change on screen that is not a list diff: a banner, a status bar, an overlay, an option
    /// picked in a sheet, a field revealed.
    public static var stateFade: Animation {
        .easeInOut(duration: stateFadeDuration)
    }

    /// How long `appear` takes.
    public static let appearDuration: Double = 0.35

    /// Something arriving or filling on its own: an empty state, a usage bar.
    public static var appear: Animation {
        .easeOut(duration: appearDuration)
    }

    /// How long `fadeOut` takes.
    public static let fadeOutDuration: Double = 0.4

    /// A highlight letting go: a tapped row's flash, the accent flood after sign in.
    public static var fadeOut: Animation {
        .easeOut(duration: fadeOutDuration)
    }

    /// A badge, a checkmark or a chip popping in on a change of its own.
    public static var pop: Animation {
        .spring(response: 0.3, dampingFraction: 0.75)
    }

    /// A control changing shape: the segmented control's pill sliding, a button collapsing into a spinner.
    public static var controlMorph: Animation {
        .spring(response: 0.35, dampingFraction: 0.8)
    }

    /// How long `toast` takes.
    public static let toastDuration: Double = 0.3

    /// A toast sliding in or out.
    public static var toast: Animation {
        .spring(duration: toastDuration)
    }

    /// A card sheet or alert rising over the screen.
    public static var sheetPresent: Animation {
        .spring(response: 0.35, dampingFraction: 0.9)
    }

    /// A card sheet or alert leaving.
    public static var sheetDismiss: Animation {
        .easeIn(duration: stateFadeDuration)
    }

    /// One page of the sign in flow giving way to the next.
    public static var pageTransition: Animation {
        .spring(response: 0.4, dampingFraction: 0.85)
    }

    /// The app moving between its top level screens (sign in and the app itself); a plain crossfade
    /// under Reduce Motion.
    public static func screenTransition(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .smooth(duration: 0.45)
    }

    /// Something that turns or sweeps for as long as work runs: a spinner, a shimmer, a busy bar.
    public static func loop(duration: Double) -> Animation {
        .linear(duration: duration).repeatForever(autoreverses: false)
    }

    /// Something that breathes for as long as a state lasts: a waiting icon, a status dot.
    public static func pulse(duration: Double) -> Animation {
        .easeInOut(duration: duration).repeatForever(autoreverses: true)
    }

    /// One step of the launch flourish; the flourish scales its own steps (`SplashView.timeScale`).
    public static func splashStep(duration: Double) -> Animation {
        .easeInOut(duration: duration)
    }

    /// The launch flourish leaving.
    public static func splashExit(duration: Double) -> Animation {
        .easeIn(duration: duration)
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

    public static let selectModeStepDuration: Duration = .milliseconds(250)

    public static let skeletonGraceDuration: Duration = .milliseconds(400)

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
