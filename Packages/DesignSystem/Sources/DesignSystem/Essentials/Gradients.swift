import SwiftUI

public extension Color {
    /// Top-leading stop of `LinearGradient.backgroundPrimary` — near `backgroundPrimary`
    /// with a faint accent tint.
    static let backgroundGradientTop = Color("BackgroundGradientTop", bundle: .module)
    /// Bottom-trailing stop of `LinearGradient.backgroundPrimary` — same tint, pushed further
    /// toward `accent` for a subtle warm glow.
    static let backgroundGradientBottom = Color("BackgroundGradientBottom", bundle: .module)
}

public extension LinearGradient {
    /// The app's default screen background: a subtle top-leading-to-bottom-trailing wash
    /// from `backgroundPrimary` toward an accent-tinted glow. Use in place of a flat
    /// `Color.backgroundPrimary` fill on full-screen containers.
    static let backgroundPrimary = LinearGradient(
        colors: [.backgroundGradientTop, .backgroundGradientBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

public extension View {
    /// Fills the view with `LinearGradient.backgroundPrimary`, ignoring safe area edges
    /// like a screen background normally would.
    func backgroundGradient() -> some View {
        background(LinearGradient.backgroundPrimary.ignoresSafeArea())
    }
}
