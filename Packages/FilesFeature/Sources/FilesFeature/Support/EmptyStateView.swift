import DesignSystem
import SwiftUI

private enum Constants {
    static let spacing: CGFloat = .space16
    static let iconSize: CGFloat = .superIcon
    /// A slow, subtle breathing pulse on the icon so an empty/error screen feels alive rather than
    /// static. Disabled under Reduce Motion.
    static let pulseScale: CGFloat = 1.05
    static let pulseDuration: Double = 2.4
    static let appearDuration: Double = 0.35
}

/// The icon and message placeholder shown across the app for load error, empty and no
/// search results states. Pass `retry` for the error case, since an empty error list often
/// can't be pulled to refresh and needs its own button. `BrowseContentView`'s no search
/// results state composes this with its own trailing "Search everywhere" content instead.
struct EmptyStateView: View {
    let icon: Image
    let message: String
    var retry: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: Constants.spacing) {
            icon
                .resizable()
                .scaledToFit()
                .foregroundColor(.secondaryDS)
                .frame(width: Constants.iconSize, height: Constants.iconSize)
                .scaleEffect(isPulsing ? Constants.pulseScale : 1)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: Constants.pulseDuration).repeatForever(autoreverses: true),
                    value: isPulsing
                )
            Text(message).type(.body1(.regular), style: .secondary)
            if let retry {
                RetryLinkButton(action: retry)
            }
        }
        .padding(.horizontal, .space16)
        .multilineTextAlignment(.center)
        // Gentle fade + rise on first appear, then start the breathing loop.
        .opacity(hasAppeared || reduceMotion ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : .space8)
        .animation(.easeOut(duration: Constants.appearDuration), value: hasAppeared)
        .onAppear {
            hasAppeared = true
            isPulsing = true
        }
    }
}

#Preview("Error") {
    EmptyStateView(icon: IconKit.warning, message: "Couldn't reach the server.", retry: {})
}

#Preview("No items") {
    EmptyStateView(icon: IconKit.folder, message: "This folder is empty.")
}

#Preview("No search results") {
    EmptyStateView(icon: IconKit.search, message: "No matches for \u{201C}vacation\u{201D}.")
}

#Preview("Long message wraps and centers") {
    EmptyStateView(
        icon: IconKit.star,
        message: "Star folders in Browse to see them here. This message is intentionally long to exercise multiline centering."
    )
}
