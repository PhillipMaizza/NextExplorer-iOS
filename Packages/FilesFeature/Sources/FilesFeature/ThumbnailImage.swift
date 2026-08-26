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
struct ThumbnailImage: View {
    let serverURL: URL
    let path: String
    let fallbackIcon: Image
    let iconTint: Color

    @State private var thumbnailURL: URL?
    @State private var didResolve = false
    @Dependency(\.filesClient) private var filesClient

    var body: some View {
        Group {
            if let thumbnailURL {
                AsyncImage(url: thumbnailURL) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        fallbackImage
                    }
                }
            } else {
                fallbackImage
            }
        }
        .task(id: path) {
            guard !didResolve else { return }
            thumbnailURL = try? await filesClient.thumbnailURL(serverURL, path)
            didResolve = true
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
