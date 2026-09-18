import DesignSystem
import SwiftUI

/// List vs grid layout for a file listing tab, persisted per tab via `@AppStorage`. Shared so
/// Favorites, Downloads (and any future listing tab) don't each re-declare the same two cases.
enum FileListViewMode: String {
    case list, grid
}

/// The grid geometry every file listing shares (Browse, Favorites, Downloads): one adaptive
/// column spec and the tile inset, so the numbers live in one place instead of a `private enum
/// Constants` copy per view.
enum FileGridMetrics {
    static let spacing: CGFloat = .space16
    /// Inset between a grid tile's content and its `backgroundSecondary` card edge.
    static let cellPadding: CGFloat = .space12
    static let adaptiveMinimum: CGFloat = 100

    static var columns: [GridItem] {
        [GridItem(.adaptive(minimum: adaptiveMinimum), spacing: spacing)]
    }
}

/// The shared shell for one row in a multi-select file listing (Favorites, Downloads): the
/// leading selection glyph while selecting, the haptic button, the grouped-card background, the
/// `.isSelected` trait, and the first/last separator suppression that makes the group read as one
/// card. Callers supply the row content plus the feature-specific swipes and context menu; the
/// shell owns nothing feature-specific, so both tabs' rows collapse to one implementation.
struct SelectableListRow<Content: View, LeadingSwipe: View, TrailingSwipe: View, Menu: View>: View {
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
            HStack(spacing: .space12) {
                if isSelecting {
                    DSSelectionIndicator(isSelected: isSelected)
                }
                content
            }
        }
        .buttonStyle(DSHapticButtonStyle())
        .accessibilityAddTraits(isSelecting && isSelected ? [.isSelected] : [])
        .listRowBackground(Color.backgroundSecondary)
        .contextMenu { menu }
        .swipeActions(edge: .leading) { leadingSwipe }
        .swipeActions(edge: .trailing) { trailingSwipe }
        .listRowSeparator(isFirst ? .hidden : .visible, edges: .top)
        .listRowSeparator(isLast ? .hidden : .visible, edges: .bottom)
    }
}

/// The grid-tile counterpart to `SelectableListRow`: the same tap + selection-glyph overlay +
/// context menu behavior, laid out as a `dsCard` tile.
struct SelectableGridCell<Content: View, Menu: View>: View {
    private let isSelecting: Bool
    private let isSelected: Bool
    private let padding: CGFloat
    private let onTap: () -> Void
    private let content: Content
    private let menu: Menu

    init(
        isSelecting: Bool,
        isSelected: Bool,
        padding: CGFloat = FileGridMetrics.cellPadding,
        onTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder contextMenu: () -> Menu = { EmptyView() }
    ) {
        self.isSelecting = isSelecting
        self.isSelected = isSelected
        self.padding = padding
        self.onTap = onTap
        self.content = content()
        menu = contextMenu()
    }

    var body: some View {
        Button(action: onTap) {
            content
                .dsCard(padding: padding)
                .overlay(alignment: .topLeading) {
                    if isSelecting {
                        DSSelectionIndicator(isSelected: isSelected)
                    }
                }
        }
        .buttonStyle(DSHapticButtonStyle())
        .hapticFeedback(.selection, trigger: isSelected)
        .contextMenu { menu }
    }
}
