import ComposableArchitecture
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let footerTopPadding: CGFloat = .space8
    static let versionLogoSize: CGFloat = .iconMedium
    static let versionLogoSpacing: CGFloat = .zero
}

/// The bottom of the Settings root: the logo and version, the credits and the tip
/// prompt.
struct SettingsVersionFooter: View {
    let store: StoreOf<SettingsFeature>

    /// "Like the app? Buy me a coffee ☕️" as one wrapping line. Only the coffee half is bold and
    /// accented so it reads as the tappable part; the lead in stays regular weight.
    private var tipPrompt: Text {
        Text(L10n.Settings.creditsLikeApp + " ").fontWeight(.regular)
            + Text(L10n.Settings.creditsBuyCoffee).fontWeight(.bold).foregroundColor(.accent)
    }

    var body: some View {
        VStack(spacing: .space16) {
            VStack(spacing: Constants.versionLogoSpacing) {
                IconKit.logo
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.versionLogoSize, height: Constants.versionLogoSize)
                Text(AppDiagnostics.versionText)
                    .type(.label4, style: .tertiary)
            }
            VStack(spacing: .space4) {
                // `.body3(.regular)` is the same 14pt/subheadline metrics as label4 but
                // regular weight (label4 is semibold, and `.type` bakes that weight in
                // too close to the Text for an outer `.fontWeight` to override).
                Text(L10n.Settings.creditsMadeBy)
                    .type(.body3(.regular), style: .tertiary)
                Button {
                    store.send(.tipJarButtonTapped)
                } label: {
                    tipPrompt.type(.label4, style: .tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, Constants.footerTopPadding)
    }
}

#Preview {
    SettingsVersionFooter(store: Store(initialState: .preview) { SettingsFeature() })
        .padding()
}
