import SwiftUI

/// Bar and transition modifiers whose targets only exist on iOS. On iOS each forwards to the
/// exact system call; on macOS, where there is no navigation, tab or bottom bar, it is a no op.
public extension View {
    /// The app accent on iOS. The Mac keeps the system accent, so its selections, buttons and
    /// sheets match every other Mac app.
    func platformAccentTint() -> some View {
        #if os(iOS)
            tint(Color.accent)
        #else
            self
        #endif
    }

    func navigationBarBackgroundHidden() -> some View {
        #if os(iOS)
            toolbarBackground(.hidden, for: .navigationBar)
        #else
            self
        #endif
    }

    func hidesNavigationBar(_ hidden: Bool) -> some View {
        #if os(iOS)
            toolbar(hidden ? .hidden : .visible, for: .navigationBar)
        #else
            self
        #endif
    }

    func hidesBottomBar(_ hidden: Bool) -> some View {
        #if os(iOS)
            toolbar(hidden ? .hidden : .visible, for: .bottomBar)
        #else
            self
        #endif
    }

    func hidesTabBar(_ hidden: Bool) -> some View {
        #if os(iOS)
            toolbar(hidden ? .hidden : .automatic, for: .tabBar)
        #else
            self
        #endif
    }

    /// Makes a grouped list row's label span the row, so a click anywhere across a Mac row
    /// (not only on its text) activates it. An iOS `List` row already does.
    func fullRowHitArea() -> some View {
        #if os(macOS)
            frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        #else
            self
        #endif
    }

    func zoomNavigationTransition(sourceID: some Hashable, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        #else
            self
        #endif
    }
}

public extension SearchFieldPlacement {
    /// Always visible search: the navigation bar drawer on iOS, the window toolbar on macOS.
    static var pinned: SearchFieldPlacement {
        #if os(iOS)
            .navigationBarDrawer(displayMode: .always)
        #else
            .toolbar
        #endif
    }
}
