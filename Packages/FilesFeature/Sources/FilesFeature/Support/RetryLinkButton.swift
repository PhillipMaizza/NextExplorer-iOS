import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let topPadding: CGFloat = .space8
}

/// The app's "Try Again" affordance: a borderless accent link with no fill or outline, used
/// wherever a load can be retried in place (list error states, the file preview failure
/// screens). Deliberately low chrome so it reads as an inline link, not a call to action.
struct RetryLinkButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(L10n.Common.retry)
                .type(.label3, style: .link)
                .padding(.top, Constants.topPadding)
        }
        .buttonStyle(DSHapticButtonStyle())
    }
}

#Preview {
    RetryLinkButton(action: {})
        .padding()
}
