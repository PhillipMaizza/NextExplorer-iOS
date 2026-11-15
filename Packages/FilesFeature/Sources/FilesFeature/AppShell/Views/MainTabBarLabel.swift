import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// A tab bar item: the title with a smaller glyph when "Show Tab Labels" is on, the full size icon on
/// its own otherwise. The title carries the accessibility label in both modes.
struct MainTabBarLabel: View {
    let showsTitle: Bool
    let title: String
    let icon: Image
    let smallIcon: Image
    let identifier: String

    var body: some View {
        if showsTitle {
            Label {
                Text(title)
            } icon: {
                tabIcon(smallIcon)
            }
            .accessibilityLabel(title)
            .accessibilityIdentifier(identifier)
        } else {
            tabIcon(icon)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
    }

    private func tabIcon(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
    }
}

#Preview("Icon only") {
    MainTabBarLabel(
        showsTitle: false,
        title: L10n.Tab.offline,
        icon: IconKit.tabDownloads,
        smallIcon: IconKit.tabDownloadsSmall,
        identifier: AccessibilityIdentifiers.Tab.downloads
    )
    .frame(width: .space32, height: .space32)
}

#Preview("With title") {
    MainTabBarLabel(
        showsTitle: true,
        title: L10n.Tab.offline,
        icon: IconKit.tabDownloads,
        smallIcon: IconKit.tabDownloadsSmall,
        identifier: AccessibilityIdentifiers.Tab.downloads
    )
}
