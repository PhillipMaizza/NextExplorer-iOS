#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    /// A By me share's right click menu: Copy (the share link, or the direct file or folder link in
    /// each mode), the system Share menu, Edit and Delete.
    struct MacSharedRowMenu: View {
        let share: Share
        let store: StoreOf<SharedFeature>
        let onToast: (DSToastMessage) -> Void

        var body: some View {
            Menu {
                Button {
                    onToast(.success(share.copyShareLink(serverURL: store.serverURL)))
                } label: {
                    Label { Text(L10n.Shared.actionShareLink) } icon: { MenuIcon.shareLink.image }
                }
                if share.directLinkChoices.count > 1 {
                    Menu {
                        directButtons
                    } label: {
                        Label { Text(L10n.Shared.direct) } icon: { MenuIcon.directLink.image }
                    }
                } else {
                    directButtons
                }
            } label: {
                Label { Text(L10n.Common.copy) } icon: { MenuIcon.copy.image }
            }
            .tint(.primaryDS)
            // The system share menu: AirDrop, Messages, Mail and the rest.
            if let url = URL(string: share.shareLink(serverURL: store.serverURL)) {
                ShareLink(item: url) {
                    Label { Text(L10n.Common.share) } icon: { MenuIcon.systemShare.image }
                }
                .tint(.primaryDS)
            }
            Section {
                Button { store.send(.editTapped(share)) } label: {
                    Label { Text(L10n.Common.edit) } icon: { MenuIcon.rename.image }
                }
                .tint(.primaryDS)
            }
            Section {
                RemovableMenuButton(title: L10n.Common.delete, icon: MenuIcon.delete.image, isRemoval: true) {
                    store.send(.deleteTapped(share))
                }
            }
        }

        private var directButtons: some View {
            ForEach(share.directLinkChoices) { choice in
                Button {
                    onToast(.success(share.copyDirectLink(serverURL: store.serverURL, mode: choice.mode)))
                } label: {
                    Text(choice.title)
                    Text(choice.detail)
                }
            }
        }
    }

    struct MacReceivedShareMenu: View {
        let share: Share
        let store: StoreOf<SharedFeature>
        let onOpen: (Share) -> Void
        let onToast: (DSToastMessage) -> Void

        var body: some View {
            Button { onOpen(share) } label: {
                Label { Text(L10n.Browse.open) } icon: { MenuIcon.open(isDirectory: share.isDirectory).image }
            }
            .tint(.primaryDS)
            if share.receivedFileItem != nil, share.isDownloadAllowed {
                Button { store.send(.downloadTapped(share)) } label: {
                    Label { Text(L10n.Browse.actionDownload) } icon: { MenuIcon.download.image }
                }
                .tint(.primaryDS)
            }
            Section {
                Button {
                    onToast(.success(share.copyShareLink(serverURL: store.serverURL)))
                } label: {
                    Label { Text(L10n.Shared.copyLink) } icon: { MenuIcon.directLink.image }
                }
                .tint(.primaryDS)
            }
        }
    }

    #Preview("Row menu") {
        macSharedPreview(.byMe) { store in
            Menu(L10n.Common.copy) {
                MacSharedRowMenu(
                    share: Share.previewSharedByMe[0],
                    store: store,
                    onToast: { _ in }
                )
            }
            .padding()
        }
        .previewCanvas(.control)
    }
#endif
