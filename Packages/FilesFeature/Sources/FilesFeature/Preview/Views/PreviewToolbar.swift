import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// The chrome every full screen media preview shares: an inline title whose menu holds the file
/// actions, a top leading close, and a bottom bar with system share and delete (or those two in
/// the title menu too, `hasBottomBar: false`). These are
/// plain `.toolbar` items inside the caller's `NavigationStack`, so the OS gives them Liquid
/// Glass, correct sizing/spacing, safe area insets and accessibility for free: the preview
/// only supplies the actions.
extension View {
    func previewChrome(
        title: String? = nil,
        systemShare: SystemShareSource = .unavailable,
        onShareLink: (() -> Void)? = nil,
        onRename: (() -> Void)? = nil,
        onDownload: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onInfo: (() -> Void)? = nil,
        onMove: (() -> Void)? = nil,
        onCopy: (() -> Void)? = nil,
        offline: PreviewOfflineAction? = nil,
        onEdit: (() -> Void)? = nil,
        hasFrostedBars: Bool = false,
        hasBottomBar: Bool = true,
        file: FileItem? = nil,
        onClose: @escaping () -> Void
    ) -> some View {
        modifier(PreviewChrome(
            offline: offline,
            onEdit: onEdit,
            hasFrostedBars: hasFrostedBars,
            hasBottomBar: hasBottomBar,
            file: file,
            title: title,
            systemShare: systemShare,
            onShareLink: onShareLink,
            onRename: onRename,
            onDownload: onDownload,
            onDelete: onDelete,
            onInfo: onInfo,
            onMove: onMove,
            onCopy: onCopy,
            onClose: onClose
        ))
    }
}

private struct PreviewChrome: ViewModifier {
    /// Set by a caller that knows the current file (the gallery); otherwise the environment's.
    let offline: PreviewOfflineAction?
    /// Opens the file on screen in the text editor; `nil` hides the button.
    let onEdit: (() -> Void)?
    /// Frosted bars that the page scrolls under; otherwise clear.
    let hasFrostedBars: Bool
    /// Share and Delete along the bottom; without it they join the title's menu, leaving the
    /// bottom of the page to the content (a video's own controls, the gallery's pages).
    let hasBottomBar: Bool
    /// The file on screen, which names the save action: a photo or video goes to Photos.
    let file: FileItem?
    @Environment(\.previewOffline) private var environmentOffline
    @Environment(\.canExportPreview) private var canExport
    let title: String?
    let systemShare: SystemShareSource
    let onShareLink: (() -> Void)?
    let onRename: (() -> Void)?
    let onDownload: (() -> Void)?
    let onDelete: (() -> Void)?
    /// Get Info, Move and Copy, like the list's long press menu; `nil` leaves one out.
    let onInfo: (() -> Void)?
    let onMove: (() -> Void)?
    let onCopy: (() -> Void)?
    let onClose: () -> Void
    /// Share started from the title menu, whose item is gone the moment it is tapped.
    @State private var shareModel = SystemShareModel()
    @State private var shareFailureToast: DSToastMessage?

    private var offlineAction: PreviewOfflineAction? {
        offline ?? environmentOffline
    }

    private var downloadTitle: String {
        #if os(macOS)
            L10n.PreviewToolbar.download
        #else
            if let file, file.isImage || file.isRawImage {
                L10n.PreviewToolbar.savePhoto
            } else if let file, file.isVideo {
                L10n.PreviewToolbar.saveVideo
            } else {
                L10n.PreviewToolbar.saveToDevice
            }
        #endif
    }

    private var downloadIcon: Image {
        IconKit.download
    }

    /// A title menu glyph in the primary color, not the accent.
    private func menuIcon(_ image: Image) -> some View {
        image.foregroundStyle(Color.primaryDS)
    }

    private var shareSource: SystemShareSource {
        canExport ? systemShare : .unavailable
    }

    private var hasSystemShare: Bool {
        if case .unavailable = shareSource {
            return false
        }
        return true
    }

    func body(content: Content) -> some View {
        #if os(macOS)
            // A sheet on the Mac shows no NavigationStack toolbar, so the chrome is a bar of its
            // own across the top, like Preview's title bar.
            content.safeAreaInset(edge: .top, spacing: 0) { macBar }
        #else
            content
                .navigationTitle(title ?? "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.bar, for: .navigationBar, .bottomBar)
                .toolbarBackgroundVisibility(hasFrostedBars ? .visible : .hidden, for: .navigationBar)
                .toolbarBackgroundVisibility(hasFrostedBars ? .visible : .automatic, for: .bottomBar)
                .toolbarTitleMenu {
                    fileActions(includesShare: !hasBottomBar, includesDelete: !hasBottomBar)
                }
                .tint(Color.primaryDS)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { onClose() } label: { IconKit.close.foregroundStyle(Color.primaryDS) }
                            .accessibilityLabelWithTooltip(L10n.PreviewToolbar.close)
                    }
                    if let onEdit {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { onEdit() } label: { IconKit.rename.foregroundStyle(Color.primaryDS) }
                                .accessibilityLabelWithTooltip(L10n.Common.edit)
                        }
                    }
                    if shareModel.isPreparing {
                        ToolbarItem(placement: .topBarTrailing) {
                            DSSpinner()
                                .accessibilityLabel(L10n.Common.loading)
                        }
                    }
                    if hasBottomBar {
                        ToolbarItemGroup(placement: .bottomBar) {
                            SystemShareButton(source: shareSource)
                            if let onDelete {
                                Spacer()
                                Button { onDelete() } label: { IconKit.delete.foregroundStyle(Color.negative) }
                                    .accessibilityLabelWithTooltip(L10n.PreviewToolbar.delete)
                            }
                        }
                    }
                }
                .systemShareSheet(shareModel)
                .onDisappear { shareModel.cancel() }
                .onChange(of: shareSource.fileID) { shareModel.cancel() }
                .onChange(of: shareModel.hasFailed) { _, hasFailed in
                    guard hasFailed else { return }
                    shareFailureToast = .failure(L10n.OpenWith.failed)
                    shareModel.clearFailure()
                }
                .dsToast($shareFailureToast)
        #endif
    }

    private var hasFileActions: Bool {
        hasMenuOnlyActions || onShareLink != nil
    }

    private var hasMenuOnlyActions: Bool {
        [onInfo, onRename, onMove, onCopy, onDownload, onDelete].contains { $0 != nil } || offlineAction != nil
    }

    /// The file's actions, grouped: about the file, sending it, keeping it, removing it. The
    /// title menu on iOS, the More menu on the Mac.
    @ViewBuilder
    private func fileActions(includesShare: Bool, includesShareLink: Bool = true, includesDelete: Bool) -> some View {
        Section {
            menuButton(L10n.Browse.actionGetInfo, icon: IconKit.info, action: onInfo)
            menuButton(L10n.PreviewToolbar.rename, icon: IconKit.rename, action: onRename)
            menuButton(MoveActionStyle.title, icon: IconKit.move, action: onMove)
            menuButton(L10n.Browse.actionCopy, icon: IconKit.copy, action: onCopy)
        }
        Section {
            menuButton(
                L10n.PreviewToolbar.createShareLink,
                icon: IconKit.shareLink,
                action: includesShareLink
                    ? onShareLink
                    : nil
            )
            if includesShare, hasSystemShare {
                Button { shareModel.prepare(shareSource) } label: {
                    Label { Text(L10n.PreviewToolbar.share) } icon: { menuIcon(IconKit.share) }
                }
                .disabled(shareModel.isPreparing)
            }
            menuButton(downloadTitle, icon: downloadIcon, action: onDownload)
        }
        if let offlineAction {
            Section {
                RemovableMenuButton(
                    title: offlineAction.isOn
                        ? L10n.Browse.actionRemoveFromOffline
                        : L10n.Browse.actionAvailableOffline,
                    icon: IconKit.availableOffline,
                    isRemoval: offlineAction.isOn,
                    action: offlineAction.toggle
                )
            }
        }
        if includesDelete, let onDelete {
            Section {
                RemovableMenuButton(title: L10n.PreviewToolbar.delete, icon: IconKit.delete, isRemoval: true) {
                    onDelete()
                }
            }
        }
    }

    /// One plain menu entry in the primary color; `nil` leaves it out.
    @ViewBuilder
    private func menuButton(_ title: String, icon: Image, action: (() -> Void)?) -> some View {
        if let action {
            Button { action() } label: {
                Label { Text(title) } icon: { menuIcon(icon) }
            }
        }
    }

    #if os(macOS)
        private var macBar: some View {
            MacPreviewBar(title: title, file: file, onClose: onClose) {
                if let onEdit {
                    MacIconButton(IconKit.rename, label: L10n.Common.edit, action: onEdit)
                }
                if hasSystemShare {
                    if file?.isUnsupportedForPreview != true {
                        MacOpenWithMenu(source: shareSource)
                    }
                    SystemShareButton(source: shareSource)
                }
                if let onShareLink {
                    MacIconButton(IconKit.link, label: L10n.PreviewToolbar.createShareLink, action: onShareLink)
                }
                if hasMenuOnlyActions {
                    Menu {
                        fileActions(includesShare: false, includesShareLink: false, includesDelete: true)
                    } label: {
                        MacIconGlyph(IconKit.ellipsis)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabelWithTooltip(L10n.Common.more)
                }
            }
        }
    #endif
}
