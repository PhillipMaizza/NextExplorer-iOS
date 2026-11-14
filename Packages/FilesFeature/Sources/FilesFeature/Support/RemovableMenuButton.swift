import DesignSystem
import Localization
import SwiftUI

/// A menu item that turns something on (Available Offline, Add to Favorites) and, once it is on,
/// takes it off. Taking it off reads as a removal, red like Delete: menu glyphs follow the tint, not
/// the role, so the red is set on both.
struct RemovableMenuButton: View {
    let title: String
    let icon: Image
    let isRemoval: Bool
    let action: () -> Void

    var body: some View {
        Button(role: isRemoval ? .destructive : nil, action: action) {
            Label { Text(title) } icon: { icon }
        }
        .tint(isRemoval ? Color.negativeText : Color.primaryDS)
    }
}

#Preview("Add and remove") {
    Menu(L10n.Common.more) {
        RemovableMenuButton(
            title: L10n.Browse.actionAvailableOffline,
            icon: IconKit.availableOffline,
            isRemoval: false
        ) {}
        RemovableMenuButton(
            title: L10n.Browse.actionRemoveFromFavorites,
            icon: IconKit.starFill,
            isRemoval: true
        ) {}
    }
    .padding()
    .background(Color.backgroundPrimary)
}
