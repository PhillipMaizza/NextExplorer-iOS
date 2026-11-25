#if os(macOS)
    import CoreModels
    import DesignSystem
    import QuickLookThumbnailing
    import SwiftUI

    private enum Metrics {
        static let iconSize: CGFloat = .size72
    }

    struct MacLocalFilePicture: View {
        let url: URL
        let item: FileItem

        @Environment(\.displayScale) private var displayScale
        @State private var image: NSImage?

        var body: some View {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(.space16)
                } else {
                    MacItemTile(kind: item.kind, isDirectory: item.isDirectory, size: Metrics.iconSize)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(item.name)
            .task(id: url) {
                let request = QLThumbnailGenerator.Request(
                    fileAt: url,
                    size: CGSize(width: MacInspectorMetrics.width, height: MacInspectorMetrics.pictureHeight),
                    scale: displayScale,
                    representationTypes: .thumbnail
                )
                let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                guard !Task.isCancelled else { return }
                image = thumbnail?.nsImage
            }
        }
    }

    #Preview("No thumbnail") {
        MacLocalFilePicture(
            url: URL(fileURLWithPath: "/nonexistent/report.pdf"),
            item: FileItem(name: "report.pdf", path: "", dateModified: .distantPast, size: 2_400_000, kind: "pdf")
        )
        .frame(width: MacInspectorMetrics.width, height: MacInspectorMetrics.pictureHeight)
        .background(Color.macRow)
    }
#endif
