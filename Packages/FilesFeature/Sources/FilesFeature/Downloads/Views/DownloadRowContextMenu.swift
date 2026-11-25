import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// The `…` / long press action menu for one local download, shared by the Downloads list rows
/// and grid cells: system share, rename, delete.
struct DownloadRowContextMenu: View {
    let store: StoreOf<OfflineTabFeature>
    let download: LocalDownload

    var body: some View {
        #if os(macOS)
            let url = download.url
            MacLocalFileMenuItems { url }
        #elseif os(iOS)
            ShareLink(item: download.url) {
                Label { Text(L10n.Common.share) } icon: { IconKit.share }
            }
            .tint(.primaryDS)
        #endif
        Button {
            store.send(.renameTapped(download))
        } label: {
            Label { Text(L10n.Browse.actionRename) } icon: { IconKit.rename }
        }
        .tint(.primaryDS)
        Divider()
        Button(role: .destructive) {
            store.send(.deleteTapped(download))
        } label: {
            Label { Text(L10n.Common.delete) } icon: { IconKit.delete }
        }
        .tint(.negative)
    }
}
