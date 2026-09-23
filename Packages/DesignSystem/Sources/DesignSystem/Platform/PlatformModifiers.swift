import SwiftUI

/// Bar and transition modifiers whose targets only exist on iOS. On iOS each forwards to the
/// exact system call; on macOS, where there is no navigation, tab or bottom bar, it is a no op.
public extension View {
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
