import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI
import FilesClient

/// Lazily resolves and displays a thumbnail for one file, falling back to `fallbackIcon`
/// while loading, on failure, or once resolved to no thumbnail (`GET /api/thumbnails/*`
/// legitimately returns `{ thumbnail: "" }` for e.g. PDFs or when thumbnails are disabled
/// server-side). One request per instance — the API has no bulk/listing variant, matching
/// how the real web client also loads these per-file.
///
/// Loads through `ThumbnailCache` rather than `AsyncImage(url:)` directly, so a thumbnail
/// already seen this session (or a prior one) is read from disk instead of re-hitting the
/// server every time the row scrolls back into view.
struct ThumbnailImage: View {
    let serverURL: URL
    let path: String
    let fallbackIcon: Image
    let iconTint: Color

    @State private var uiImage: UIImage?
    @State private var didResolve = false
    @Dependency(\.filesClient) private var filesClient
    @Dependency(\.thumbnailCache) private var thumbnailCache

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackImage
            }
        }
        .task(id: path) {
            guard !didResolve else { return }
            defer { didResolve = true }
            guard let thumbnailURL = try? await filesClient.thumbnailURL(serverURL, path) else { return }
            guard let data = try? await thumbnailCache.data(thumbnailURL) else { return }
            uiImage = UIImage(data: data)
        }
    }

    private var fallbackImage: some View {
        fallbackIcon
            .resizable()
            .scaledToFit()
            .foregroundStyle(iconTint)
    }
}

#Preview("Falls back to icon (previewValue has no thumbnails)") {
    ThumbnailImage(
        serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
        path: "Photos/vacation.jpg",
        fallbackIcon: IconKit.document,
        iconTint: .secondaryDS
    )
    .frame(width: .iconMedium, height: .iconMedium)
    .padding(.space16)
}
