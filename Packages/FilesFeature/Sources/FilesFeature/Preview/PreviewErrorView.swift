import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let spacing: CGFloat = .space16
}

/// A preview that could not load: the warning, the reason, and a retry when the load can be asked
/// again, so a passing network error is not a dead end that forces closing the preview.
struct PreviewErrorView: View {
    let message: String
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: Constants.spacing) {
            IconKit.warning
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.negative)
                .frame(width: .iconMedium, height: .iconMedium)
            Text(message)
                .type(.body1(.regular), style: .secondary)
                .multilineTextAlignment(.center)
            if let onRetry {
                RetryLinkButton(action: onRetry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, .space16)
    }
}

#Preview("With retry") {
    PreviewErrorView(message: L10n.TextPreview.loadFailed, onRetry: {})
}

#Preview("Without retry") {
    PreviewErrorView(message: L10n.Gallery.loadFailed)
}
