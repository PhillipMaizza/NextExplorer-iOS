import DesignSystem
import Localization
import SwiftUI

/// Explains what a "server" is on the first login screen and points newcomers at the setup
/// guide, so someone who opened the app without a NextExplorer instance isn't stuck staring at
/// an address field. Presented from the `(i)` button beside the "Where's your instance" title.
struct ServerInfoSheet: View {
    let onClose: () -> Void
    @Environment(\.openURL) private var openURL

    private enum Constants {
        static let maxHeightFraction: CGFloat = 0.8
        static let setupGuide = URL(string: "https://github.com/nxzai/NextExplorer/blob/main/docs/index.md")
    }

    var body: some View {
        DSDynamicHeightSheet(maxHeightFraction: Constants.maxHeightFraction) {
            VStack(alignment: .leading, spacing: .space24) {
                DSSheetHeader(
                    icon: IconKit.info,
                    title: L10n.Login.serverInfoTitle,
                    closeAccessibilityLabel: L10n.Common.close,
                    onClose: onClose
                )
                Text(L10n.Login.serverInfoBody)
                    .type(.body1(.regular), style: .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, .space24)
            .padding(.vertical, .space24)
        } footer: {
            DSSheetFooter {
                HStack(spacing: .space12) {
                    DSButton(L10n.Common.close, style: .outline, action: onClose)
                    DSButton(L10n.Login.serverInfoGuide, style: .primary) {
                        guard let url = Constants.setupGuide else { return }
                        openURL(url)
                    }
                }
            }
        }
    }
}

#Preview {
    Color.backgroundPrimary
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ServerInfoSheet(onClose: {})
        }
}
