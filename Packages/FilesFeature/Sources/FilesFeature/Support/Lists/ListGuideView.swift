#if os(iOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let tileSize: CGFloat = .size64
    }

    struct ListGuideView: View {
        let guide: ListGuide

        var body: some View {
            EmptyGuide(title: title) {
                EmptyGuideTile(icon: icon, size: Metrics.tileSize)
            } detail: {
                detail
            }
            .accessibilityElement(children: .combine)
        }

        private var title: String {
            switch guide {
            case .favorites: L10n.EmptyGuide.favoritesTitle
            case .sharedByMe: L10n.EmptyGuide.sharedTitle
            case .sharedWithMe: L10n.EmptyGuide.sharedWithMeTitle
            case .offline: L10n.EmptyGuide.offlineTitleDevice
            case .trash: L10n.EmptyGuide.trashTitle
            case .browseRootUnassigned: L10n.EmptyGuide.browseRootUnassignedTitle
            case .browseRootNoVolumes: L10n.EmptyGuide.browseRootNoVolumesTitle
            case .readOnlyFolder: L10n.EmptyGuide.readOnlyTitle
            case .folderMissing: L10n.EmptyGuide.folderMissingTitle
            case .serverProblem: L10n.EmptyGuide.serverProblemTitle
            }
        }

        private var icon: Image {
            switch guide {
            case .favorites: IconKit.star
            case .sharedByMe, .sharedWithMe: IconKit.shareLink
            case .offline: IconKit.availableOffline
            case .trash: IconKit.delete
            case .browseRootUnassigned, .browseRootNoVolumes: IconKit.server
            case .readOnlyFolder: IconKit.lock
            case .folderMissing: IconKit.folder
            case .serverProblem: IconKit.warning
            }
        }

        @ViewBuilder
        private var detail: some View {
            switch guide {
            case .favorites:
                message(L10n.EmptyGuide.favoritesBodyTouch(L10n.Browse.actionAddToFavorites, L10n.Favorites.actionEdit))
            case .sharedByMe:
                message(L10n.EmptyGuide.sharedBodyTouch(L10n.Browse.actionShare))
            case .sharedWithMe:
                message(L10n.Shared.emptyWithMe)
            case .offline:
                message(L10n.EmptyGuide.offlineBodyTouch(L10n.Browse.actionAvailableOffline))
            case let .trash(retentionDays):
                if let retentionDays {
                    EmptyGuideBullet(icon: IconKit.time, text: L10n.Trash.subtitle(retentionDays))
                }
                EmptyGuideBullet(icon: IconKit.restore, text: L10n.EmptyGuide.trashRestore)
                EmptyGuideBullet(icon: IconKit.shareLink, text: L10n.EmptyGuide.trashShareLinks)
            case .browseRootUnassigned:
                message(L10n.EmptyGuide.browseRootUnassignedBody)
            case .browseRootNoVolumes:
                EmptyGuideBullet(icon: IconKit.folder, text: L10n.EmptyGuide.browseRootVolumeFolders)
                EmptyGuideBullet(icon: IconKit.server, text: L10n.EmptyGuide.browseRootAddFolder)
            case let .readOnlyFolder(canDownload):
                EmptyGuideBullet(
                    icon: IconKit.eye,
                    text: canDownload ? L10n.EmptyGuide.readOnlyOpen : L10n.EmptyGuide.readOnlyOpenOnly
                )
                EmptyGuideBullet(icon: IconKit.lock, text: L10n.EmptyGuide.readOnlyLocked)
            case .folderMissing:
                message(L10n.EmptyGuide.folderMissingBody)
            case .serverProblem:
                message(L10n.EmptyGuide.serverProblemBody)
            }
        }

        private func message(_ text: String) -> some View {
            Text(text)
                .type(.body1(.regular), style: .secondary)
        }
    }

    #Preview("Favorites") {
        ListGuideView(guide: .favorites)
            .background(Color.backgroundPrimary)
    }

    #Preview("Trash, dark") {
        ListGuideView(guide: .trash(retentionDays: 30))
            .background(Color.backgroundPrimary)
            .preferredColorScheme(.dark)
    }

    #Preview("Read only folder") {
        ListGuideView(guide: .readOnlyFolder(canDownload: true))
            .background(Color.backgroundPrimary)
    }

    #Preview("Browse root, no volumes") {
        ListGuideView(guide: .browseRootNoVolumes)
            .background(Color.backgroundPrimary)
    }
#endif
