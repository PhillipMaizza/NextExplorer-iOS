import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import SwiftUI
import UIKit

private enum Constants {
    /// PDF's file kind, for the `FileTypeIcon` fallback.
    static let kind = "pdf"
    static let cornerRadius: CGFloat = .size4
    /// The reveal when a render lands: the page springs up from a slight shrink while the
    /// placeholder fades out under it.
    static let revealAnimation: Animation = .spring(response: 0.4, dampingFraction: 0.7)
    static let revealInitialScale: CGFloat = 0.86
}

/// A PDF's browse thumbnail: a loading placeholder while its first page is fetched and
/// rendered on device in the background, then the rendered page on its own. Falls back to
/// `FileTypeIcon(kind: "pdf")` (which carries its own "PDF" banner) for a file that is too
/// large or that PDFKit can't open.
///
/// The work is owned by `PDFThumbnailStore`, not this view: the fetch + render run in a task
/// a scroll or navigation doesn't cancel, and the result is published back through this
/// key's observed `Entry`, so revisiting a folder finds its thumbnails already done.
struct PDFThumbnailImage: View {
    let serverURL: URL
    let item: FileItem

    @Dependency(\.filesClient) private var filesClient
    @Dependency(\.pdfThumbnailCache) private var pdfThumbnailCache
    private let store = PDFThumbnailStore.shared

    private var cacheKey: String {
        PDFThumbnailCache.cacheKey(id: item.id, signature: item.cacheSignature)
    }

    var body: some View {
        // `entry(forKey:)` is a stable per-key box; only its `state` is observed, so a
        // resolving thumbnail redraws just this cell.
        let entry = store.entry(forKey: cacheKey)
        let state = entry.state
        return GeometryReader { proxy in
            content(state: state)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .animation(Constants.revealAnimation, value: state.isReady)
        .task(id: cacheKey) {
            store.load(
                entry: entry, key: cacheKey, item: item, serverURL: serverURL,
                filesClient: filesClient, cache: pdfThumbnailCache
            )
        }
    }

    @ViewBuilder
    private func content(state: PDFThumbnailStore.State) -> some View {
        switch state {
        case let .ready(image):
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius))
                .transition(.asymmetric(
                    insertion: .scale(scale: Constants.revealInitialScale).combined(with: .opacity),
                    removal: .opacity
                ))
        case .unavailable:
            FileTypeIcon(kind: Constants.kind)
                .transition(.opacity)
        case .loading:
            ThumbnailLoadingPlaceholder()
                .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius))
                .transition(.opacity)
        }
    }
}

#Preview("Loading placeholder (previewValue never produces a render)") {
    PDFThumbnailImage(
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        item: FileItem(name: "report.pdf", path: "Documents", dateModified: Date(), size: 800_000, kind: "pdf")
    )
    .frame(width: .iconLarge, height: .iconLarge)
    .padding(.space16)
}
