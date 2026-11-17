import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// The "Select / Sort / Grid-List" toolbar chrome shared by Browse, Favorites, and Downloads:
/// the ellipsis menu with a "Select" entry, the top-left Select All/Deselect All button plus
/// trailing Cancel once selecting, and the grid/list toggle. What differs per screen: the
/// sort menu's actual options, and what shows in the bottom bar while selecting: stays with
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
                .buttonStyle(DSPressableButtonStyle())
                .accessibilityLabelWithTooltip(isAllSelected ? L10n.Select.deselectAll : L10n.Select.selectAll)
            }
            ToolbarItem(placement: .primaryAction) {
                SelectModeCancelButton(action: onCancel)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    clipboardMenu()
                    if isSelectAvailable {
                        Button {
                            // Select mode swaps this menu's button for Cancel, so it waits for the
                            // menu to close into its button first; swapped at once, the menu popped off.
                            Task {
                                try? await DSMotion.waitForStep(DSMotion.menuCloseDuration)
                                onSelectModeToggled()
                            }
                        } label: {
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
                // Menu glyphs follow the tint: primary like the system's own menus, not the accent.
                .tint(Color.primaryDS)
                .accessibilityLabelWithTooltip(L10n.Common.more)
                .accessibilityIdentifier(AccessibilityIdentifiers.Browse.moreMenu)
            }
        }
    #endif
}

/// Cancel while selecting: hides the circles first through the screen's `selectModeChrome`, then
/// ends select mode; with no chrome around it, it ends select mode at once.
struct SelectModeCancelButton: View {
    let action: () -> Void
    @Environment(\.leaveSelectMode) private var leaveSelectMode

    var body: some View {
        Button(L10n.Common.cancel) {
            if let leaveSelectMode {
                leaveSelectMode { action() }
            } else {
                action()
            }
        }
        .buttonStyle(DSPressableButtonStyle())
    }
}

#Preview("Cancel") {
    SelectModeCancelButton {}
        .padding(.space16)
}
