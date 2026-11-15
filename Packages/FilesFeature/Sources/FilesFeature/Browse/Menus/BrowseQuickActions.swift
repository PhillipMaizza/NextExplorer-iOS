import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// One action a Browse item offers without opening its menu: a list row's swipe action, and the
/// same action as a VoiceOver action on a grid tile, which has no swipe.
struct BrowseQuickAction: Identifiable {
    let title: String
    let icon: Image
    let tint: Color
    var isEnabled = true
    let perform: () -> Void

    var id: String {
        title
    }
}

@MainActor
extension BrowseQuickAction {
    /// What `item` offers on this screen; nothing while selecting, where a tap picks instead.
    static func actions(for item: FileItem, store: StoreOf<BrowseFeature>) -> [BrowseQuickAction] {
        guard !store.isSelecting else { return [] }
        var actions: [BrowseQuickAction] = []
        // Device content cannot be deleted, only taken off the device, as on the tab's own rows.
        if store.showsDeviceContent, store.offlineItemIDs.contains(item.id) {
            actions.append(BrowseQuickAction(
                title: L10n.Browse.actionRemoveFromOffline,
                icon: IconKit.delete,
                tint: .negative,
                perform: { store.send(.offlineToggleTapped(item)) }
            ))
        }
        if store.access?.canDelete ?? false {
            actions.append(BrowseQuickAction(
                title: L10n.Common.delete,
                icon: IconKit.delete,
                tint: .negative,
                perform: { store.send(.deleteTapped(item)) }
            ))
        }
        // Only folders can be favorited: the server 400s on anything else.
        if item.isDirectory, !store.showsDeviceContent {
            let isFavorite = store.favoritePaths.contains(item.id)
            actions.append(BrowseQuickAction(
                title: isFavorite ? L10n.Browse.actionRemoveFromFavorites : L10n.Browse.actionAddToFavorites,
                icon: isFavorite ? IconKit.starFill : IconKit.star,
                tint: .accent,
                isEnabled: store.hasLoadedFavorites,
                perform: { store.send(.favoriteToggleButtonTapped(item)) }
            ))
        }
        if store.access?.canWrite ?? false {
            actions.append(BrowseQuickAction(
                title: L10n.Browse.actionRename,
                icon: IconKit.rename,
                tint: .positive,
                perform: { store.send(.renameTapped(item)) }
            ))
        }
        return actions
    }
}

/// The quick actions as buttons: icons tinted for a swipe, or named for VoiceOver.
struct BrowseQuickActionButtons: View {
    enum Style {
        case swipe
        case accessibility
    }

    let actions: [BrowseQuickAction]
    let style: Style

    var body: some View {
        ForEach(actions) { action in
            switch style {
            case .swipe:
                Button(action: action.perform) { action.icon }
                    .tint(action.tint)
                    .disabled(!action.isEnabled)
                    .accessibilityLabel(action.title)
            case .accessibility:
                if action.isEnabled {
                    Button(action.title, action: action.perform)
                }
            }
        }
    }
}

#Preview("Swipe") {
    List {
        Text(verbatim: "notes.txt")
            .swipeActions(edge: .trailing) {
                BrowseQuickActionButtons(
                    actions: [
                        BrowseQuickAction(
                            title: L10n.Common.delete,
                            icon: IconKit.delete,
                            tint: .negative,
                            perform: {}
                        ),
                        BrowseQuickAction(
                            title: L10n.Browse.actionRename,
                            icon: IconKit.rename,
                            tint: .positive,
                            perform: {}
                        ),
                    ],
                    style: .swipe
                )
            }
    }
}
