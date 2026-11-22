import DesignSystem
import SwiftUI

/// A login page's own surface: frosted in the floating card (regular width), the full bleed gradient
/// on compact. Each page carries one, so the outgoing page blurs rather than shows through mid slide.
struct LoginPageSurface: View {
    let horizontalSizeClass: UserInterfaceSizeClass?

    var body: some View {
        #if os(macOS)
            Color.macCard
        #else
            if horizontalSizeClass == .regular {
                DSSheetSurface()
            } else {
                LinearGradient.backgroundPrimary.ignoresSafeArea()
            }
        #endif
    }
}

#Preview("Card") {
    ZStack {
        LinearGradient.accent.ignoresSafeArea()
        LoginPageSurface(horizontalSizeClass: .regular)
            .frame(width: 320, height: 420)
            .clipShape(RoundedRectangle(cornerRadius: .radiusCard, style: .continuous))
    }
}

#Preview("Compact") {
    LoginPageSurface(horizontalSizeClass: .compact)
}
