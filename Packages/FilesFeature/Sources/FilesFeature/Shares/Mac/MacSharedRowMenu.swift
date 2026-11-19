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
                    Label { Text(L10n.Shared.actionShareLink) } icon: { IconKit.shareLink }
                }
                Menu {
                    ForEach(DirectLinkMode.allCases) { mode in
                        Button(mode.title) {
                            onToast(.success(share.copyDirectLink(serverURL: store.serverURL, mode: mode)))
                        }
                    }
                } label: {
                    Label {
                        Text(share.isDirectory ? L10n.Shared.actionFolderLink : L10n.Shared.actionFileLink)
                    } icon: {
                        IconKit.link
                    }
                }
            } label: {
                Label { Text(L10n.Common.copy) } icon: { IconKit.copy }
            }
            // The system share menu: AirDrop, Messages, Mail and the rest.
            if let url = URL(string: share.shareLink(serverURL: store.serverURL)) {
                ShareLink(item: url) {
                    Label { Text(L10n.Common.share) } icon: { IconKit.share }
                }
            }
            Divider()
            Button { store.send(.editTapped(share)) } label: {
                Label { Text(L10n.Common.edit) } icon: { IconKit.rename }
            }
            Button(role: .destructive) { store.send(.deleteTapped(share)) } label: {
                Label { Text(L10n.Common.delete) } icon: { IconKit.delete }
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
