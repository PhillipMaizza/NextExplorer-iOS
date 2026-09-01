import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let spacing: CGFloat = .space16
    static let iconSize: CGFloat = .superIcon
    static let retryTopPadding: CGFloat = .space8
    static let retryInnerVerticalPadding: CGFloat = .space12
    static let retryInnerHorizontalPadding: CGFloat = .space24
    static let retryCornerRadius: CGFloat = .radiusControl
}

/// The icon and message placeholder shown across the app for load error, empty and no
/// search results states. Pass `retry` for the error case, since an empty error list often
/// can't be pulled to refresh and needs its own button. `BrowseContentView`'s no search
/// results state composes this with its own trailing "Search everywhere" content instead.
struct EmptyStateView: View {
    let icon: Image
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: Constants.spacing) {
            icon
                .resizable()
                .scaledToFit()
                .foregroundColor(.secondaryDS)
                .frame(width: Constants.iconSize, height: Constants.iconSize)
            Text(message).type(.body1(.regular), style: .secondary)
            if let retry {
                Button(action: retry, label: {
                    Text(L10n.Common.retry)
                        .type(.label3, style: .link)
                        .padding(.vertical, Constants.retryInnerVerticalPadding)
                        .padding(.horizontal, Constants.retryInnerVerticalPadding)
                })
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.retryCornerRadius)
                        .strokeBorder(Color.accent, lineWidth: .borderWidthFocused)
                )

                    .padding(.top, Constants.retryTopPadding)
            }
        }
        .padding(.horizontal, .space16)
        .multilineTextAlignment(.center)
    }
}

#Preview("Error") {
    EmptyStateView(icon: IconKit.warning, message: "Couldn't reach the server.", retry: { })
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
