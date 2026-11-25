import DesignSystem
import SwiftUI

/// List vs grid layout for a file listing tab, persisted per tab via `@AppStorage`. Shared so
/// Favorites, Downloads (and any future listing tab) don't each redeclare the same two cases.
enum FileListViewMode: String {
    case list, grid
}

/// The grid geometry every file listing shares (Browse, Favorites, Offline), so the numbers live in
/// one place instead of a `private enum Constants` copy per view.
enum FileGridMetrics {
    /// Between columns, and between folder cards.
    static let spacing: CGFloat = .space12
    /// Between rows of files: a little more than between columns, since each tile ends in text.
    static let rowSpacing: CGFloat = .space16
    static let margin: CGFloat = .space16
    static let sectionSpacing: CGFloat = .space24
    static let headerSpacing: CGFloat = .space8
    /// What a grid holds decides its columns: both follow the grid size, folder cards a step roomier.
    enum Content {
        case files
        case folders
    }

    static func columns(for content: Content, size: ThumbnailSize, isCompact: Bool) -> [GridItem] {
        switch (content, isCompact) {
        case (.files, true):
            Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: size.columnCount)
        case (.folders, true):
            Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: size.folderColumnCount)
        case (.files, false):
            [GridItem(.adaptive(minimum: size.minimumColumnWidth), spacing: spacing, alignment: .top)]
        case (.folders, false):
            [GridItem(.adaptive(minimum: size.minimumFolderColumnWidth), spacing: spacing, alignment: .top)]
        }
    }
}

/// The shared shell for one row in a multiselect file listing (Favorites, Downloads): the
/// leading selection glyph while selecting, the pressable button, the grouped card background, the
/// `.isSelected` trait, and the first/last separator suppression that makes the group read as one
/// card. Callers supply the row content plus the feature specific swipes and context menu; the
/// shell owns nothing feature specific, so both tabs' rows collapse to one implementation.
struct SelectableListRow<Content: View, LeadingSwipe: View, TrailingSwipe: View, Menu: View>: View {
    /// What a finger slide in select mode knows this row by (see `dragToSelect`).
    private let selectionID: String
    private let isSelecting: Bool
    private let isSelected: Bool
    private let isFirst: Bool
    private let isLast: Bool
    private let onTap: () -> Void
    private let content: Content
    private let leadingSwipe: LeadingSwipe
    private let trailingSwipe: TrailingSwipe
    private let menu: Menu

    init(
        selectionID: String,
        isSelecting: Bool,
        isSelected: Bool,
        isFirst: Bool,
        isLast: Bool,
        onTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder leadingSwipe: () -> LeadingSwipe = { EmptyView() },
        @ViewBuilder trailingSwipe: () -> TrailingSwipe = { EmptyView() },
        @ViewBuilder contextMenu: () -> Menu = { EmptyView() }
    ) {
        self.selectionID = selectionID
        self.isSelecting = isSelecting
        self.isSelected = isSelected
        self.isFirst = isFirst
        self.isLast = isLast
        self.onTap = onTap
        self.content = content()
        self.leadingSwipe = leadingSwipe()
        self.trailingSwipe = trailingSwipe()
        menu = contextMenu()
    }

    var body: some View {
        Button(action: onTap) {
            content
                .dsListSelection(isSelecting: isSelecting, isSelected: isSelected)
                .dragSelectable(id: selectionID)
        }
        .buttonStyle(DSPressableButtonStyle())
        .accessibilityAddTraits(isSelecting && isSelected ? [.isSelected] : [])
        .listRowBackground(Color.backgroundSecondary)
        .contextMenu { menu }
        .swipeActions(edge: .leading) { leadingSwipe }
        .swipeActions(edge: .trailing) { trailingSwipe }
        .listRowSeparator(isFirst ? .hidden : .visible, edges: .top)
        .listRowSeparator(isLast ? .hidden : .visible, edges: .bottom)
    }
}

/// The grid tile counterpart to `SelectableListRow`: the same tap, selection and context
/// menu behavior, laid out as a `dsGridTile`.
struct SelectableGridCell<Content: View, Menu: View>: View {
    private let selectionID: String
    private let isSelecting: Bool
    private let isSelected: Bool
    private let onTap: () -> Void
    private let content: Content
    private let menu: Menu

    init(
        selectionID: String,
        isSelecting: Bool,
        isSelected: Bool,
        onTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder contextMenu: () -> Menu = { EmptyView() }
    ) {
        self.selectionID = selectionID
        self.isSelecting = isSelecting
        self.isSelected = isSelected
        self.onTap = onTap
        self.content = content()
        menu = contextMenu()
    }

    var body: some View {
        Button(action: onTap) {
            content
                .dsGridTile(isSelecting: isSelecting, isSelected: isSelected)
                .dragSelectable(id: selectionID)
        }
        .buttonStyle(DSPressableButtonStyle())
        .contextMenu { menu }
    }
}

extension BrowseBreadcrumbBarMetrics {
    /// On a Mac every Browse mode but grid is the table, which needs no breadcrumb bar: the
    /// window already carries the back button and folder title. On iOS only the split view detail
    /// (iPad, an open iPhone Duo) shows it: an iPhone relies on the back button's history menu.
    static func isShown(browseViewModeRaw: String, isSplitViewDetail: Bool) -> Bool {
        #if os(macOS)
            browseViewModeRaw == FileListViewMode.grid.rawValue
        #else
            isSplitViewDetail
        #endif
    }
}
