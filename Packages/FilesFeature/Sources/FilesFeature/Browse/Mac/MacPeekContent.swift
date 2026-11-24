#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    struct MacPeekContent: View {
        enum Kind: Equatable {
            case folder
            case image
            case media
            case text
            case document
            case wholeFile
            case summary

            static let maxTextBytes: Int64 = 2 * 1_024 * 1_024
            static let byteLimit: Int64 = 100 * 1_024 * 1_024

            init(_ item: FileItem, isSavedOffline: Bool) {
                guard !item.isDirectory else {
                    self = .folder
                    return
                }
                let preview = Self.preview(of: item)
                let isTooLarge = preview.isFetchedWhole && !isSavedOffline && item.size > Self.byteLimit
                self = isTooLarge ? .summary : preview
            }

            private static func preview(of item: FileItem) -> Kind {
                guard !item.isUnsupportedForPreview, !item.isArchive else { return .summary }
                switch PreviewKind(item) {
                case .image: return .image
                case .media: return .media
                case .text where item.size <= maxTextBytes: return .text
                case .document: return .document
                case .archive, .unsupported: return .summary
                default: return .wholeFile
                }
            }

            var isFetchedWhole: Bool {
                switch self {
                case .image, .document, .wholeFile: true
                case .folder, .media, .text, .summary: false
                }
            }
        }

        let item: FileItem
        let serverURL: URL
        let isSavedOffline: Bool
        let shouldShowThumbnails: Bool
        let showsHiddenFiles: Bool

        @Dependency(\.filesClient) private var filesClient
        @State private var isPlaying = false

        var body: some View {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(item.id)
        }

        @ViewBuilder
        private var content: some View {
            switch Kind(item, isSavedOffline: isSavedOffline) {
            case .folder:
                MacPeekFolder(
                    item: item,
                    serverURL: serverURL,
                    shouldShowThumbnails: shouldShowThumbnails,
                    showsHiddenFiles: showsHiddenFiles
                )
            case .image:
                ImageGalleryPage(item: item, serverURL: serverURL)
            case .media:
                MediaGalleryPage(item: item, serverURL: serverURL, isPlaying: isPlaying) {
                    isPlaying = true
                }
            case .text:
                GalleryFetchedPage(
                    isNear: true,
                    failureMessage: L10n.TextPreview.loadFailed,
                    fetch: { [filesClient, serverURL, path = item.id] in
                        try await filesClient.fetchTextContent(serverURL, path)
                    },
                    content: { text in
                        TextDocumentBody(
                            item: item,
                            serverURL: serverURL,
                            kind: item.kind,
                            content: text,
                            text: .constant(text)
                        )
                        .padding(.space16)
                    }
                )
            case .document:
                GalleryFetchedPage(
                    isNear: true,
                    failureMessage: L10n.EmptyState.loadFailed,
                    fetch: { [filesClient, serverURL, item] in
                        try await filesClient.previewDocument(serverURL, item)
                    },
                    content: { QuickLookPreview(url: $0) }
                )
            case .summary:
                FileSummaryView(item: item, message: nil)
            case .wholeFile:
                GalleryFetchedPage(
                    isNear: true,
                    failureMessage: L10n.EmptyState.loadFailed,
                    fetch: { [filesClient, serverURL, item] in
                        if let preview = try? await filesClient.previewFile(serverURL, item) {
                            return preview
                        }
                        return try await filesClient.downloadRawFile(serverURL, item)
                    },
                    content: { QuickLookPreview(url: $0) }
                )
            }
        }
    }

    private enum PreviewFixture {
        static let serverURL = URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")

        static func item(_ name: String, kind: String, size: Int64 = 2_400_000) -> FileItem {
            FileItem(name: name, path: "Documents", dateModified: .distantPast, size: size, kind: kind)
        }

        @MainActor
        static func content(_ item: FileItem) -> some View {
            MacPeekContent(
                item: item,
                serverURL: serverURL,
                isSavedOffline: false,
                shouldShowThumbnails: true,
                showsHiddenFiles: false
            )
            .frame(width: MacPeekMetrics.previewWidth, height: MacPeekMetrics.previewHeight)
            .background(Color.macCard)
        }
    }

    #Preview("Photo") {
        PreviewFixture.content(PreviewFixture.item("portrait.jpg", kind: "jpg"))
    }

    #Preview("Video") {
        PreviewFixture.content(PreviewFixture.item("Trip.mov", kind: "mov"))
    }

    #Preview("Text") {
        PreviewFixture.content(PreviewFixture.item("Meeting Notes.md", kind: "md", size: 6_000))
    }

    #Preview("PDF") {
        PreviewFixture.content(PreviewFixture.item("report.pdf", kind: "pdf"))
    }

    #Preview("No preview") {
        PreviewFixture.content(PreviewFixture.item("installer.dmg", kind: "dmg", size: 16_384))
    }

    #Preview("Other file") {
        PreviewFixture.content(PreviewFixture.item("font.otf", kind: "otf"))
    }
#endif
