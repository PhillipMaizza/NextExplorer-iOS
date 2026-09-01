import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// The `…` / long-press action menu for one local download, shared by the Downloads list rows
/// and grid cells. Open-in-Files (documents-location only), system share, rename, delete.
struct DownloadRowContextMenu: View {
    let store: StoreOf<DownloadsFeature>
    let download: LocalDownload
    let openURL: OpenURLAction

    var body: some View {
        if let filesAppURL {
            Button {
                openURL(filesAppURL)
            } label: {
                Label { Text(L10n.Downloads.actionOpenInFiles) } icon: { IconKit.folder }
            }
            .tint(.primaryDS)
            Divider()
        }
        ShareLink(item: download.url) {
            Label { Text(L10n.Common.share) } icon: { IconKit.share }
        }
        .tint(.primaryDS)
        Button {
            store.send(.renameTapped(download))
        } label: {
            Label { Text(L10n.Browse.actionRename) } icon: { IconKit.rename }
        }
        .tint(.primaryDS)
        Button(role: .destructive) {
            store.send(.deleteTapped(download))
        } label: {
            Label { Text(L10n.Common.delete) } icon: { IconKit.delete }
        }
        .tint(.negative)
    }

    /// Deep-links the Files app straight to this file (`LSSupportsOpeningDocumentsInPlace`/
    /// `UIFileSharingEnabled`, set in Info.plist, expose the app's Documents folder there) —
    /// `nil` for `.cache`-location downloads, which are app-private and never show up in
    /// Files regardless of scheme.
    private var filesAppURL: URL? {
        guard download.location == .documents else { return nil }
        guard var components = URLComponents(url: download.url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "shareddocuments"
        return components.url
    }
}
