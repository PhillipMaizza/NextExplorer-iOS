import SwiftUI

public extension View {
    /// Liquid Glass on iOS 26, frosted `.ultraThinMaterial` fallback below it. For floating
    /// controls that sit over arbitrary content — full-screen preview toolbars, close-button
    /// chips — where the system toolbar can't reach (custom `fullScreenCover` with its own
    /// swipe-to-dismiss). Pass `interactive: true` on a tappable control so the glass reacts
    /// to touch the way system glass buttons do.
    @ViewBuilder
    func dsGlass(interactive: Bool = false, in shape: some Shape = Capsule()) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(shape.fill(.ultraThinMaterial))
        }
    }
}
