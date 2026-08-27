import DesignSystem
import SwiftUI

/// The "Select / Sort / Grid-List" toolbar chrome shared by Browse, Favorites, and Downloads:
/// the ellipsis menu with a "Select" entry, the top-left Select All/Deselect All button plus
/// trailing Cancel once selecting, and the grid/list toggle. What differs per screen — the
/// sort menu's actual options, and what shows in the bottom bar while selecting — stays with
/// each caller rather than being forced into this shared shape.
@MainActor
@ToolbarContentBuilder
func selectSortToolbar<SortMenu: View>(
    isSelecting: Bool,
    isAllSelected: Bool,
    isSelectAvailable: Bool,
    isGridView: Bool,
    onSelectModeToggled: @escaping () -> Void,
    onSelectAllToggled: @escaping () -> Void,
    onCancel: @escaping () -> Void,
    onToggleViewMode: @escaping () -> Void,
    @ViewBuilder sortMenu: () -> SortMenu
) -> some ToolbarContent {
    if isSelecting {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: onSelectAllToggled) {
                IconKit.selectAll
            }
            .buttonStyle(DSHapticButtonStyle())
            .accessibilityLabel(isAllSelected ? "Deselect All" : "Select All")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Cancel", action: onCancel)
                .buttonStyle(DSHapticButtonStyle())
        }
    } else {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if isSelectAvailable {
                    Button(action: onSelectModeToggled) {
                        Label { Text("Select") } icon: { IconKit.select }
                    }
                }
                sortMenu()
                Button(action: onToggleViewMode) {
                    Label {
                        Text(isGridView ? "List View" : "Grid View")
                    } icon: {
                        isGridView ? IconKit.listBullet : IconKit.squareGrid
                    }
                }
            } label: {
                IconKit.moreOptions
            }
        }
    }
}
