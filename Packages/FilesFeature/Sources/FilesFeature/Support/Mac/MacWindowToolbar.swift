#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    extension View {
        /// The Mac window's toolbar for the app's screens: Upload, Refresh and Search at the trailing
        /// edge. Shared centers its picker and keeps Refresh to the menu and ⌘R.
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
        @FocusedValue(\.sharedSegment) private var sharedSegment

        func body(content: Content) -> some View {
            content
                .toolbar {
                    if let sharedSegment {
                        ToolbarItem(placement: .principal) {
                            Picker(L10n.Shared.navigationTitle, selection: sharedSegment) {
                                ForEach(SharedFeature.Segment.allCases, id: \.self) { segment in
                                    Text(segment.title).tag(segment)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
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
                    // Shared refreshes from View › Refresh and ⌘R only.
                    if let refresh, sharedSegment == nil {
                        ToolbarItem(placement: .primaryAction) {
                            MacRefreshToolbarButton(isRefreshing: refresh.isRefreshing) { refresh() }
                        }
                    }
                    if let search, search.showsToolbarButton {
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
        /// Shared's By me or With me, published while Shared is on show.
        @Entry var sharedSegment: Binding<SharedFeature.Segment>?
    }

    #Preview("Upload, Refresh and Search") {
        NavigationStack {
            Text(verbatim: "Folder contents")
                .frame(width: 600, height: 300)
                .focusedSceneValue(\.uploadToVisibleFolder, UploadToVisibleFolderAction {})
                .focusedSceneValue(\.refreshVisibleScreen, RefreshScreenAction(isRefreshing: false) {})
                .focusedSceneValue(\.focusSearchField, FocusSearchAction {})
        }
        .macWindowToolbar()
    }
#endif
