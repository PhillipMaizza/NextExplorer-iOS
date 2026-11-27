#if os(iOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    /// A document Quick Look shows (Word, Excel, Keynote and the like), opened full screen from its
    /// gallery page. Quick Look draws these out of process and takes every swipe, so they open on
    /// their own instead of inside the pager.
    struct QuickLookCover: View {
        let item: FileItem
        let serverURL: URL
        let onDismiss: () -> Void

        @Dependency(\.filesClient) private var filesClient

        var body: some View {
            let filesClient = filesClient
            let serverURL = serverURL
            let item = item
            NavigationStack {
                GalleryFetchedPage(
                    isNear: true,
                    failureMessage: L10n.EmptyState.loadFailed,
                    fetch: { try await filesClient.previewDocument(serverURL, item) },
                    content: { QuickLookPreview(url: $0).ignoresSafeArea() }
                )
                .backgroundGradient()
                .previewChrome(
                    title: item.name,
                    systemShare: .remote(item, serverURL: serverURL),
                    file: item,
                    onClose: onDismiss
                )
            }
        }
    }

    #Preview("Document") {
        QuickLookCover(
            item: FileItem(name: "budget.xlsx", path: "", dateModified: .distantPast, size: 24_576, kind: "xlsx"),
            serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
            onDismiss: {}
        )
    }
#endif
