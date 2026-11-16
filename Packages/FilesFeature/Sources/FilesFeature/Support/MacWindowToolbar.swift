#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    extension View {
        /// The trailing buttons of a Mac window showing the app's screens: Upload, Refresh, Search.
        func macWindowToolbar() -> some View {
            modifier(MacWindowToolbar())
        }
    }

    /// Declared once per window rather than by each screen: items a pushed screen declares again in
    /// the slots of the screen before it lose their glass, drawing nothing or taking no clicks. The
    /// screen on show still decides, through the actions it publishes (the ones ⌘R and ⌘F also run).
    private struct MacWindowToolbar: ViewModifier {
        @FocusedValue(\.uploadToVisibleFolder) private var upload
        @FocusedValue(\.refreshVisibleScreen) private var refresh
        @FocusedValue(\.focusSearchField) private var search

        func body(content: Content) -> some View {
            content
                .toolbar {
                    // Pins the buttons to the trailing edge, past anything a screen puts in the middle
                    // (Shared's By me / With me picker).
                    if #available(macOS 26.0, *) {
                        ToolbarSpacer(.flexible)
                    }
                    if let upload {
                        ToolbarItem(placement: .primaryAction) {
                            Button { upload() } label: { IconKit.upload }
                                .tint(Color.accent)
                                .accessibilityLabelWithTooltip(L10n.Uploads.actionUploadFromFiles)
                                .accessibilityIdentifier(AccessibilityIdentifiers.Browse.uploadMenu)
                        }
                    }
                    if let refresh {
                        ToolbarItem(placement: .primaryAction) {
                            MacRefreshToolbarButton(isRefreshing: refresh.isRefreshing) { refresh() }
                        }
                    }
                    if let search {
                        ToolbarItem(placement: .primaryAction) {
                            MacSearchButton(action: search)
                        }
                    }
                }
        }
    }

    /// Opens the file picker for the folder on screen; published by `BrowseContentView`.
    struct UploadToVisibleFolderAction {
        let perform: () -> Void

        func callAsFunction() {
            perform()
        }
    }

    extension FocusedValues {
        @Entry var uploadToVisibleFolder: UploadToVisibleFolderAction?
    }
#endif
