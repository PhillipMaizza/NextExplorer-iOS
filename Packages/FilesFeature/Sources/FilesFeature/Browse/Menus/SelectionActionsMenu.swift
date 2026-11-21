import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// The select mode bar's one menu, holding every action on the selection, grouped like the gallery's
/// title menu: about and moving the files, sending them, keeping them, then Delete on its own.
/// Actions that need exactly one item are left out while several are selected, rather than shown
/// greyed out.
struct SelectionActionsMenu: View {
    /// What the current selection allows; the screen works these out from its access and items.
    struct Availability: Equatable {
        var single: FileItem?
        /// Off on a screen pushed from the Offline tab, where only actions on kept files are offered.
        var canGetInfo = true
        var canWrite = false
        var canShare = false
        /// Share hands the kept copies to the system share sheet (device content), for any number of
        /// files, instead of creating a link for one.
        var canShareKept = false
        var canTransfer = false
        /// A move deletes the original, so it also needs the right to delete.
        var canMove = false
        var canDelete = false
        var canSave = false
        var canKeepOffline = false
        var offlineAction: OfflineBulkAction?
        var canFavorite = false
        var isAllFavorite = false
        var hasLoadedFavorites = true

        /// Whether the menu would list anything for this selection: with nothing, the button is
        /// disabled rather than opening an empty menu (device content with no kept pick).
        var hasActions: Bool {
            let singleActions = single != nil && (canGetInfo || canWrite || canShare)
            return singleActions || canTransfer || canShareKept || canSave || canKeepOffline || canFavorite
                || canDelete
        }
    }

    let availability: Availability
    let onInfo: (FileItem) -> Void
    let onRename: (FileItem) -> Void
    let onShareLink: (FileItem) -> Void
    var onShareKept: () -> Void = {}
    let onCopy: () -> Void
    let onMove: () -> Void
    let onSave: () -> Void
    let onOffline: () -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void

    private enum Constants {
        static let iconSize: CGFloat = .iconMedium
    }

    var body: some View {
        Menu {
            Section {
                if let single = availability.single {
                    if availability.canGetInfo {
                        item(L10n.Browse.actionGetInfo, IconKit.info) { onInfo(single) }
                    }
                    if availability.canWrite {
                        item(L10n.Browse.actionRename, IconKit.rename) { onRename(single) }
                    }
                }
                if availability.canTransfer {
                    item(L10n.Browse.actionCopy, IconKit.copy, action: onCopy)
                    if availability.canMove {
                        item(L10n.Browse.actionMove, IconKit.move, action: onMove)
                    }
                }
            }
            Section {
                if availability.canShareKept {
                    item(L10n.PreviewToolbar.share, IconKit.share, action: onShareKept)
                } else if let single = availability.single, availability.canShare {
                    item(L10n.Browse.actionShare, IconKit.shareLink) { onShareLink(single) }
                }
                if availability.canSave {
                    item(SaveActionStyle.title, SaveActionStyle.icon, action: onSave)
                }
            }
            Section {
                if availability.canKeepOffline {
                    let action = availability.offlineAction
                    RemovableMenuButton(
                        title: action?.title ?? L10n.Browse.actionAvailableOffline,
                        icon: action?.icon ?? IconKit.availableOffline,
                        isRemoval: action == .remove,
                        action: onOffline
                    )
                    .disabled(action == nil)
                }
                if availability.canFavorite {
                    RemovableMenuButton(
                        title: availability.isAllFavorite
                            ? L10n.Browse.actionRemoveFromFavorites
                            : L10n.Browse.actionAddToFavorites,
                        icon: availability.isAllFavorite ? IconKit.starFill : IconKit.star,
                        isRemoval: availability.isAllFavorite,
                        action: onFavorite
                    )
                    .disabled(!availability.hasLoadedFavorites)
                }
            }
            if availability.canDelete {
                Section {
                    Button(role: .destructive, action: onDelete) {
                        Label { Text(L10n.Browse.actionDelete) } icon: { IconKit.delete }
                    }
                    .tint(.red)
                }
            }
        } label: {
            IconKit.moreOptions
                .resizable()
                .scaledToFit()
                .frame(width: Constants.iconSize, height: Constants.iconSize)
                .foregroundStyle(Color.primaryDS)
        }
        // Menu glyphs follow the tint: primary like the system's own menus, not the accent.
        .tint(Color.primaryDS)
        .disabled(!availability.hasActions)
        .accessibilityLabel(L10n.Common.more)
    }

    private func item(_ title: String, _ icon: Image, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(title) } icon: { icon }
        }
    }
}

@MainActor
private enum PreviewSample {
    static let report = FileItem(name: "report.pdf", path: "Docs", dateModified: .distantPast, size: 2_048, kind: "pdf")

    static func menu(_ availability: SelectionActionsMenu.Availability) -> some View {
        SelectionActionsMenu(
            availability: availability,
            onInfo: { _ in },
            onRename: { _ in },
            onShareLink: { _ in },
            onCopy: {},
            onMove: {},
            onSave: {},
            onOffline: {},
            onFavorite: {},
            onDelete: {}
        )
        .padding()
        .background(Color.backgroundPrimary)
    }
}

#Preview("One file") {
    PreviewSample.menu(.init(
        single: PreviewSample.report,
        canWrite: true,
        canShare: true,
        canTransfer: true,
        canMove: true,
        canDelete: true,
        canSave: true,
        canKeepOffline: true,
        offlineAction: .add
    ))
}

#Preview("Several folders, all favorites and offline") {
    PreviewSample.menu(.init(
        canTransfer: true,
        canKeepOffline: true,
        offlineAction: .remove,
        canFavorite: true,
        isAllFavorite: true
    ))
}

#Preview("Inside a folder kept offline") {
    PreviewSample.menu(.init(
        single: PreviewSample.report,
        canGetInfo: false,
        canShareKept: true,
        canSave: true,
        canKeepOffline: true,
        offlineAction: .remove
    ))
}

#Preview("Read only") {
    PreviewSample.menu(.init(canTransfer: true))
}

#Preview("Offline, nothing kept picked") {
    PreviewSample.menu(.init(single: PreviewSample.report, canGetInfo: false))
}
