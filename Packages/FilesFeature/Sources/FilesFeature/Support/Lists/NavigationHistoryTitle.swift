import SwiftUI

extension View {
    /// Names the screen for the back button's long press menu while the bar itself stays empty:
    /// the visible title lives in `PinnedTitleSearchHeader`. An empty principal item hides the
    /// bar title but leaves it as the screen's name in the navigation history, and the back
    /// button stays a bare chevron. The Mac window keeps no title of its own.
    func navigationHistoryTitle(_ title: String) -> some View {
        #if os(iOS)
            navigationTitle(title)
                .toolbarRole(.editor)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Color.clear
                            .frame(width: 0, height: 0)
                            .accessibilityHidden(true)
                    }
                }
        #else
            navigationTitle("")
        #endif
    }
}
