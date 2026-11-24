#if os(macOS)
    import SwiftUI

    /// What the Edit and File menus can do to the focused file table's selection.
    public struct BrowseKeyboardActions {
        public let cut: () -> Void
        public let copy: () -> Void
        public let duplicate: () -> Void
        /// Undoes the last file operation; does nothing when none is waiting.
        public let undo: () -> Void
        public let paste: () -> Void
        public let delete: () -> Void
        public let rename: () -> Void
        public let selectAll: () -> Void
        public let getInfo: () -> Void
        public let canPaste: Bool
        /// File ▸ Open (⌘O, ⌘↓): opens the one selected item.
        public var open: () -> Void = {}
        /// Edit ▸ Copy Path (⌥⌘C): the selection's server paths, one per line.
        public var copyPath: () -> Void = {}
        /// Does the last undone operation again; does nothing when none is waiting.
        public var redo: () -> Void = {}
    }

    /// The visible Browse screen's sort, for the View menu's Sort By.
    public struct BrowseViewOptions {
        public let sortOption: BrowseFeature.SortOption
        public let sortDirection: BrowseFeature.SortDirection
        public let setSortOption: (BrowseFeature.SortOption) -> Void
        public let setSortDirection: (BrowseFeature.SortDirection) -> Void
    }

    public extension BrowseFeature.SortOption {
        var menuTitle: String {
            title
        }
    }

    public extension BrowseFeature.SortDirection {
        var menuTitle: String {
            title
        }
    }

    public struct FocusedMenuAction {
        let perform: () -> Void

        public func callAsFunction() {
            perform()
        }
    }

    public extension FocusedValues {
        @Entry var browseKeyboardActions: BrowseKeyboardActions?
        @Entry var duplicateBrowseSelection: FocusedMenuAction?
        @Entry var archiveFolderBack: FocusedMenuAction?
        @Entry var browseViewOptions: BrowseViewOptions?
    }

    @MainActor
    extension BrowseKeyboardActions {
        /// Does nothing, for previews of the views that take it.
        static let preview = BrowseKeyboardActions(
            cut: {}, copy: {}, duplicate: {}, undo: {}, paste: {},
            delete: {}, rename: {}, selectAll: {}, getInfo: {}, canPaste: false
        )
    }
#endif
