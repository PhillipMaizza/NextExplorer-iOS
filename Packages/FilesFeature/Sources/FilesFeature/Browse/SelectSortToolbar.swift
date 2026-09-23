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
    macViewModes: MacViewModes? = nil,
    hasClipboardItems: Bool = false,
    @ViewBuilder extraViewModes: () -> some View = { EmptyView() },
    @ViewBuilder clipboardMenu: () -> some View = { EmptyView() },
    @ViewBuilder sortMenu: () -> some View
) -> some ToolbarContent {
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
        #if os(macOS)
            // A Mac toolbar has room: every action the iOS "…" menu hides is a direct control.
            ToolbarItemGroup(placement: .primaryAction) {
                if hasClipboardItems {
                    Menu {
                        clipboardMenu()
                    } label: {
                        IconKit.paste
                    }
                    .accessibilityLabelWithTooltip(L10n.Browse.actionPaste)
                }
                if isSelectAvailable {
                    Button(action: onSelectModeToggled) {
                        IconKit.select
                    }
                    .accessibilityLabelWithTooltip(L10n.Common.select)
                }
                sortMenu()
                    .labelStyle(.iconOnly)
                if let macViewModes {
                    Picker(selection: macViewModes.selection) {
                        ForEach(macViewModes.options) { option in
                            option.icon
                                .help(option.title)
                                .accessibilityLabel(option.title)
                                .tag(option.id)
                        }
                    } label: {
                        Text(L10n.Select.viewAs)
                    }
                    .pickerStyle(.segmented)
                    .help(L10n.Select.viewAs)
                } else {
                    Button(action: onToggleViewMode) {
                        isGridView ? IconKit.listBullet : IconKit.squareGrid
                    }
                    .accessibilityLabelWithTooltip(isGridView ? L10n.Select.listView : L10n.Select.gridView)
                }
            }
        #else
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
        #endif
    }
}

/// The view modes a Mac toolbar offers as a segmented picker, stored as the screen's raw
/// view mode string.
struct MacViewModes {
    struct Option: Identifiable {
        let id: String
        let title: String
        let icon: Image
    }

    let options: [Option]
    let selection: Binding<String>

    /// List and grid, the modes every file list screen has.
    static func listAndGrid(_ selection: Binding<String>) -> MacViewModes {
        MacViewModes(options: [
            Option(id: FileListViewMode.list.rawValue, title: L10n.Select.listView, icon: IconKit.listBullet),
            Option(id: FileListViewMode.grid.rawValue, title: L10n.Select.gridView, icon: IconKit.squareGrid),
        ], selection: selection)
    }
}
