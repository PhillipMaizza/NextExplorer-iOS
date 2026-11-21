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

extension MainTabBarLabel {
    /// The item for `tab`, filled while it is the selected one.
    init(tab: MainTabFeature.Tab, isSelected: Bool, showsTitle: Bool) {
        let (title, icons): (String, (fill: Image, line: Image, smallFill: Image, smallLine: Image)) = switch tab {
        case .browse: (
                L10n.Tab.browse,
                (IconKit.tabBrowseFill, IconKit.tabBrowse, IconKit.tabBrowseFillSmall, IconKit.tabBrowseSmall)
            )
        case .favorites: (
                L10n.Tab.favorites,
                (
                    IconKit.tabFavoritesFill,
                    IconKit.tabFavorites,
                    IconKit.tabFavoritesFillSmall,
                    IconKit.tabFavoritesSmall
                )
            )
        case .shared: (
                L10n.Tab.shared,
                (IconKit.tabShareFill, IconKit.tabShare, IconKit.tabShareFillSmall, IconKit.tabShareSmall)
            )
        case .downloads: (
                L10n.Tab.offline,
                (
                    IconKit.tabDownloadsFill,
                    IconKit.tabDownloads,
                    IconKit.tabDownloadsFillSmall,
                    IconKit.tabDownloadsSmall
                )
            )
        case .settings: (
                L10n.Tab.settings,
                (IconKit.tabSettingsFill, IconKit.tabSettings, IconKit.tabSettingsFillSmall, IconKit.tabSettingsSmall)
            )
        case .trash: (L10n.Trash.title, (IconKit.delete, IconKit.delete, IconKit.delete, IconKit.delete))
        }
        self.init(
            showsTitle: showsTitle,
            title: title,
            icon: isSelected ? icons.fill : icons.line,
            smallIcon: isSelected ? icons.smallFill : icons.smallLine,
            identifier: MainTabSidebar.identifier(for: tab)
        )
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

#Preview("Selected, with title") {
    MainTabBarLabel(tab: .favorites, isSelected: true, showsTitle: true)
}
