import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let size: CGFloat = 6
}

/// The small dot beside Offline in the sidebar while it holds files kept since it was last opened.
/// VoiceOver reads it as "New files available offline".
struct NewFilesDot: View {
    var body: some View {
        Circle()
            .fill(Color.accent)
            .frame(width: Constants.size, height: Constants.size)
            .accessibilityElement()
            .accessibilityLabel(L10n.Offline.newFilesBadge)
    }
}

#Preview("Dot") {
    HStack {
        Label { Text(L10n.Tab.offline) } icon: { IconKit.availableOffline }
        Spacer()
        NewFilesDot()
    }
    .padding()
    .frame(width: 240)
}
