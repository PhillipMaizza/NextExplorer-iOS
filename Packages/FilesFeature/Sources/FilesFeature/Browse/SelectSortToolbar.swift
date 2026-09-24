import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// The "Select / Sort / Grid-List" toolbar chrome shared by Browse, Favorites, and Downloads:
/// the ellipsis menu with a "Select" entry, the top-left Select All/Deselect All button plus
/// trailing Cancel once selecting, and the grid/list toggle. What differs per screen — the
/// sort menu's actual options, and what shows in the bottom bar while selecting — stays with
/// each caller rather than being forced into this shared shape.
@MainActor
@ToolbarContentBuilder
func selectSortToolbar(
    isSelecting: Bool,
    isAllSelected: Bool,
    isSelectAvailable: Bool,
    isGridView: Bool,
    onSelectModeToggled: @escaping () -> Void,
    onSelectAllToggled: @escaping () -> Void,
    onCancel: @escaping () -> Void,
    onToggleViewMode: @escaping () -> Void,
    hasClipboardItems: Bool = false,
    @ViewBuilder extraViewModes: () -> some View = { EmptyView() },
    @ViewBuilder clipboardMenu: () -> some View = { EmptyView() },
    @ViewBuilder sortMenu: () -> some View
) -> some ToolbarContent {
    #if os(macOS)
        // Mac file lists are tables that select natively, so there is no select mode and
        // no view toggle; the toolbar keeps only sort and paste.
        ToolbarItemGroup(placement: .navigation) {
            sortMenu()
                .labelStyle(.iconOnly)
        }
        ToolbarItemGroup(placement: .principal) {
            if hasClipboardItems {
                Menu {
                    clipboardMenu()
                } label: {
                    IconKit.paste
                }
                .accessibilityLabelWithTooltip(L10n.Browse.actionPaste)
            }
        }
    #else
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onSelectAllToggled) {
                    IconKit.selectAll
                }
                .buttonStyle(DSHapticButtonStyle())
                .accessibilityLabelWithTooltip(isAllSelected ? L10n.Select.deselectAll : L10n.Select.selectAll)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.Common.cancel, action: onCancel)
                    .buttonStyle(DSHapticButtonStyle())
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    clipboardMenu()
                    if isSelectAvailable {
                        Button(action: onSelectModeToggled) {
                            Label { Text(L10n.Common.select) } icon: { IconKit.select }
                        }
                    }
                    sortMenu()
                    Button(action: onToggleViewMode) {
                        Label {
                            Text(isGridView ? L10n.Select.listView : L10n.Select.gridView)
                        } icon: {
                            isGridView ? IconKit.listBullet : IconKit.squareGrid
                        }
                    }
                    extraViewModes()
                } label: {
                    IconKit.moreOptions.foregroundStyle(Color.primaryDS)
                }
                .accessibilityLabelWithTooltip(L10n.Common.more)
                .accessibilityIdentifier(AccessibilityIdentifiers.Browse.moreMenu)
            }
        }
    #endif
}
