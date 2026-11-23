#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    private enum Metrics {
        static let pictureMaxPixels: CGFloat = 1024
        static let paperTopInset: CGFloat = .size20
        static let paperSideInset: CGFloat = .space24
        static let paperRadius: CGFloat = .radiusSmall
        static let paperShadowRadius: CGFloat = 1.5
        static let paperShadowOffset: CGFloat = 1
        static let maxTextBytes: Int64 = 2 * 1_024 * 1_024
    }

    struct MacInspectorPreview: View {
        enum Kind: Equatable {
            case picture
            case video
            case text
            case document
            case documentPicture

            init?(_ item: FileItem) {
                guard !item.isDirectory else { return nil }
                switch PreviewKind(item) {
                case .media where item.isVideo:
                    self = .video
                case .text where item.size > 0 && item.size <= Metrics.maxTextBytes:
                    self = .text
                case .document where DocumentThumbnailStore.isEligible(item):
                    self = .document
                default:
                    if item.supportsThumbnail || ThumbnailImage.shouldReadOwnContent(kind: item.kind) {
                        self = .picture
                    } else if DocumentThumbnailStore.isEligible(item) {
                        self = .documentPicture
                    } else {
                        return nil
                    }
                }
            }
        }

        let item: FileItem
        let kind: Kind
        let serverURL: URL

        @Dependency(\.filesClient) private var filesClient
        @State private var isSettled = false
        @State private var isPlaying = false

        var body: some View {
            content
                .task(id: item.id) {
                    isSettled = false
                    isPlaying = false
                    try? await Task.sleep(for: MacInspectorMetrics.followDelay)
                    guard !Task.isCancelled else { return }
                    isSettled = true
                }
        }

        @ViewBuilder
        private var content: some View {
            switch kind {
            case .picture:
                ThumbnailImage(
                    serverURL: serverURL,
                    path: item.id,
                    signature: item.cacheSignature,
                    fallbackIcon: IconKit.document,
                    fallbackKind: item.kind,
                    iconTint: Color.secondaryDS,
                    maxPixelDimension: Metrics.pictureMaxPixels,
                    fileSize: item.size,
                    modified: item.dateModified,
                    fill: .backdrop
                )
            case .video:
                MediaGalleryPage(item: item, serverURL: serverURL, isPlaying: isPlaying) {
                    isPlaying = true
                }
            case .text:
                paper {
                    GalleryFetchedPage(
                        isNear: isSettled,
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
                            .padding(.space12)
                        }
                    )
                }
            case .document:
                paper {
                    GalleryFetchedPage(
                        isNear: isSettled,
                        failureMessage: L10n.EmptyState.loadFailed,
                        fetch: { [filesClient, serverURL, item] in
                            try await filesClient.previewDocument(serverURL, item)
                        },
                        content: { QuickLookPreview(url: $0) }
                    )
                }
            case .documentPicture:
                DocumentThumbnailImage(serverURL: serverURL, item: item, isGridWell: true) {
                    FileKindChip(kind: item.kind)
                }
            }
        }

        private func paper(@ViewBuilder _ page: () -> some View) -> some View {
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: Metrics.paperRadius,
                topTrailingRadius: Metrics.paperRadius,
                style: .continuous
            )
            return page()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.macCard)
                .clipShape(shape)
                .shadow(color: .macCardShadow, radius: Metrics.paperShadowRadius, y: Metrics.paperShadowOffset)
                .padding(.top, Metrics.paperTopInset)
                .padding(.horizontal, Metrics.paperSideInset)
        }
    }

    private enum PreviewFixture {
        static let serverURL = URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")

        static func item(_ name: String, kind: String, size: Int64 = 2_400_000) -> FileItem {
            FileItem(name: name, path: "Documents", dateModified: .distantPast, size: size, kind: kind)
        }

        @MainActor
        static func square(_ item: FileItem) -> some View {
            Group {
                if let kind = MacInspectorPreview.Kind(item) {
                    MacInspectorPreview(item: item, kind: kind, serverURL: serverURL)
                }
            }
            .frame(
                width: MacInspectorMetrics.width - 2 * MacInspectorMetrics.padding,
                height: MacInspectorMetrics.pictureHeight
            )
            .background(Color.macRow)
            .clipShape(RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous))
            .padding(MacInspectorMetrics.padding)
            .background(Color.macCard)
        }
    }

    #Preview("Photo") {
        PreviewFixture.square(PreviewFixture.item("portrait.jpg", kind: "jpg"))
    }

    #Preview("Music") {
        PreviewFixture.square(PreviewFixture.item("song.mp3", kind: "mp3"))
    }

    #Preview("Video") {
        PreviewFixture.square(PreviewFixture.item("Trip.mov", kind: "mov"))
    }

    #Preview("Text") {
        PreviewFixture.square(PreviewFixture.item("Meeting Notes.md", kind: "md", size: 6_000))
    }

    #Preview("PDF") {
        PreviewFixture.square(PreviewFixture.item("report.pdf", kind: "pdf"))
    }
#endif
