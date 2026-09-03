import SwiftUI

public extension View {
    /// Liquid Glass on iOS 26, frosted `.ultraThinMaterial` fallback below it. For floating
    /// controls that sit over arbitrary content — full-screen preview toolbars, close-button
    /// chips — where the system toolbar can't reach (custom `fullScreenCover` with its own
    /// swipe-to-dismiss). Pass `interactive: true` on a tappable control so the glass reacts
    /// to touch the way system glass buttons do.
    ///
    /// Honors Reduce Transparency: when that setting is on, both the glass and the material are
    /// swapped for an opaque `backgroundSecondary` fill so nothing behind the control bleeds
    /// through.
    func dsGlass(interactive: Bool = false, in shape: some Shape = Capsule()) -> some View {
        modifier(DSGlassModifier(interactive: interactive, shape: shape))
    }
}

private struct DSGlassModifier<S: Shape>: ViewModifier {
    let interactive: Bool
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(shape.fill(Color.backgroundSecondary))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content.background(shape.fill(.ultraThinMaterial))
        }
    }
}
