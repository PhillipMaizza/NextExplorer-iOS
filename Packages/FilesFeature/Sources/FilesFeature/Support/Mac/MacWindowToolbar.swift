#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    extension View {
        /// A folder window's toolbar: Refresh, Upload and Get Info at the trailing edge.
        func macWindowToolbar() -> some View {
            modifier(MacWindowToolbar())
        }
    }

    private struct MacWindowToolbar: ViewModifier {
        @FocusedValue(\.uploadToVisibleFolder) private var upload
        @FocusedValue(\.refreshVisibleScreen) private var refresh
        @FocusedValue(\.sharedSegment) private var sharedSegment
        @FocusedValue(\.openMacInspector) private var openInspector

        func body(content: Content) -> some View {
            content
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        MacWindowActions(
                            upload: upload,
                            refresh: refresh,
                            isShared: sharedSegment != nil,
                            openInspector: openInspector
                        )
                    }
                    .macPlainToolbarItem()
                }
        }
    }

    struct MacWindowActions: View {
        let upload: UploadToVisibleFolderAction?
        let refresh: RefreshScreenAction?
        let isShared: Bool
        let openInspector: MacInspectorAction?
        var closeInspector: MacInspectorAction?
        var uploads: MacUploadsActivity?

        var body: some View {
            HStack(spacing: MacToolbarMetrics.gap) {
                if let refresh, !isShared {
                    MacRefreshToolbarButton(isRefreshing: refresh.isRefreshing) { refresh() }
                }
                if let uploads {
                    MacUploadsActivityButton(activity: uploads)
                } else if let upload {
                    Button { upload() } label: { IconKit.upload.macToolbarGlyph() }
                        .buttonStyle(.macToolbarCircle)
                        .accessibilityLabelWithTooltip(L10n.Uploads.actionUploadFromFiles)
                        .accessibilityIdentifier(AccessibilityIdentifiers.Browse.uploadMenu)
                }
                if openInspector != nil || closeInspector != nil {
                    Button {
                        if let closeInspector {
                            closeInspector()
                        } else {
                            openInspector?()
                        }
                    } label: { IconKit.macToolbarInspector.macToolbarGlyph() }
                        .buttonStyle(.macToolbarCircle)
                        .accessibilityLabelWithTooltip(
                            closeInspector == nil ? L10n.Browse.actionGetInfo : L10n.Menu.hideInspector
                        )
                }
            }
        }
    }

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
                .previewCanvas(.window)
                .focusedSceneValue(\.uploadToVisibleFolder, UploadToVisibleFolderAction {})
                .focusedSceneValue(\.refreshVisibleScreen, RefreshScreenAction(isRefreshing: false) {})
                .focusedSceneValue(\.focusSearchField, FocusSearchAction {})
        }
        .macWindowToolbar()
    }
#endif
