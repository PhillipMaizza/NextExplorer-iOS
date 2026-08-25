import DesignSystem
import SwiftUI

private enum Constants {
    static let spacing: CGFloat = .space8
    static let iconSize: CGFloat = .superIcon
}

/// The icon-plus-message placeholder shown by `BrowseContentView` and `FavoritesView` for
/// their loading-error/no-items/no-search-results states. `BrowseContentView`'s "no search
/// results" state additionally offers a "Search everywhere" action, so it composes this
/// view with its own trailing content rather than being expressed by it.
struct EmptyStateView: View {
    let icon: Image
    let message: String

    var body: some View {
        VStack(spacing: Constants.spacing) {
            icon
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Constants.iconSize, height: Constants.iconSize)
            Text(message).type(.body1(.regular), style: .secondary)
        }
        .padding(.space16)
        .multilineTextAlignment(.center)
    }
}

#Preview("Error") {
    EmptyStateView(icon: IconKit.exclamationmarkTriangle, message: "Couldn't reach the server.")
}

#Preview("No items") {
    EmptyStateView(icon: IconKit.folder, message: "This folder is empty.")
}

#Preview("No search results") {
    EmptyStateView(icon: IconKit.magnifyingGlass, message: "No matches for \u{201C}vacation\u{201D}.")
}

#Preview("Long message wraps and centers") {
    EmptyStateView(
        icon: IconKit.star,
        message: "Star folders in Browse to see them here. This message is intentionally long to exercise multiline centering."
    )
}
