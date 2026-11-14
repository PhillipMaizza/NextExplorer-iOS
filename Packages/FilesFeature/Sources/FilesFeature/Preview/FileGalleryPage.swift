#if os(iOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    /// One page of the gallery, shown the way its kind needs: an image decoded in place, a video or
    /// audio file that plays in place, a PDF drawn by PDFKit, a text file read only, a zip, rar or
    /// office document with an Open button (Quick Look and the archive browser take every swipe, so
    /// they open on their own), or the summary of a file with no viewer.
    struct FileGalleryPage: View {
        let item: FileItem
        let serverURL: URL
        /// Near the page on screen: only then does a page hold decoded or fetched content.
        let isNear: Bool
        let preload: GalleryPreload
        let isPlaying: Bool
        /// The space the bars take at the top and bottom: text and PDFs start below the title and
        /// scroll under the frosted bars, a playing video keeps its controls clear of them.
        var barInsets = EdgeInsets()
        let onPlay: () -> Void
        let onOpen: () -> Void
        /// Shows or hides the bars, for pages whose own view takes the tap.
        var onToggleBars: () -> Void = {}

        @Dependency(\.filesClient) private var filesClient

        var body: some View {
            switch PreviewKind(item) {
            case .image:
                // Without this each page stops at the safe area while the pager steps by the full
                // width, so on iPhone Duo's inner panel the next page peeks in.
                ImageGalleryPage(item: item, serverURL: serverURL, isNear: isNear)
                    .ignoresSafeArea()
            case .media:
                MediaGalleryPage(
                    item: item,
                    serverURL: serverURL,
                    isPlaying: isPlaying,
                    contentInsets: barInsets,
                    onPlay: onPlay
                )
                .ignoresSafeArea()
            case .document where item.isPDF:
                pdfPage
                    .ignoresSafeArea()
            case .text:
                textPage
                    .background(Color.backgroundPrimary)
                    .ignoresSafeArea()
            case .document, .archive:
                FileSummaryView(item: item) {
                    DSButton(L10n.Browse.open, icon: IconKit.openInApp, style: .primary, action: onOpen)
                }
                .ignoresSafeArea()
            case .unsupported:
                FileSummaryView(item: item, message: L10n.UnsupportedPreview.cannotOpen)
                    .ignoresSafeArea()
            }
        }

        private var pdfPage: some View {
            let filesClient = filesClient
            let serverURL = serverURL
            let item = item
            return GalleryFetchedPage(
                isNear: isNear,
                preloaded: preload.fileURL(for: item),
                failureMessage: L10n.EmptyState.loadFailed,
                fetch: { try await filesClient.previewDocument(serverURL, item) },
                content: { PDFGalleryPage(fileURL: $0, contentInsets: barInsets) }
            )
        }

        private var textPage: some View {
            let filesClient = filesClient
            let serverURL = serverURL
            let path = item.id
            return GalleryFetchedPage(
                isNear: isNear,
                preloaded: preload.text(for: item),
                failureMessage: L10n.TextPreview.loadFailed,
                fetch: { try await filesClient.fetchTextContent(serverURL, path) },
                content: { text in
                    TextDocumentBody(
                        item: item,
                        serverURL: serverURL,
                        kind: item.kind,
                        content: text,
                        text: .constant(text),
                        contentInsets: barInsets,
                        onTap: onToggleBars
                    )
                }
            )
        }
    }

    private enum PreviewSample {
        static let serverURL = URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")

        @MainActor
        static func page(_ name: String, kind: String, preload: GalleryPreload = GalleryPreload()) -> FileGalleryPage {
            FileGalleryPage(
                item: FileItem(name: name, path: "Docs", dateModified: .distantPast, size: 2_048, kind: kind),
                serverURL: serverURL,
                isNear: true,
                preload: preload,
                isPlaying: false,
                onPlay: {},
                onOpen: {}
            )
        }
    }

    #Preview("Text") {
        PreviewSample.page(
            "notes.txt",
            kind: "txt",
            preload: GalleryPreload(itemID: "Docs/notes.txt", text: "Meeting notes\n\nShip the gallery.")
        )
    }

    #Preview("Document loading") {
        PreviewSample.page("report.pdf", kind: "pdf")
    }

    #Preview("Office document") {
        PreviewSample.page("budget.xlsx", kind: "xlsx")
    }

    #Preview("Archive") {
        PreviewSample.page("photos.zip", kind: "zip")
    }

    #Preview("Unsupported") {
        PreviewSample.page("disk.img", kind: "img")
    }

    #Preview("Video") {
        PreviewSample.page("clip.mp4", kind: "mp4")
    }
#endif
