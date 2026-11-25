#if os(macOS)
    import CoreModels
    import DesignSystem
    import SwiftUI

    private enum Metrics {
        static let pictureRadius: CGFloat = .radiusMedium
        static let pictureInset: CGFloat = .space8
        static let iconSize: CGFloat = .size72
    }

    struct MacInspectorHeader: View {
        let item: FileItem
        let subtitle: String
        let serverURL: URL
        var badge: String?
        var shouldShowThumbnails = true
        var localFile: URL?
        let onClose: () -> Void

        private var previewKind: MacInspectorPreview.Kind? {
            shouldShowThumbnails ? MacInspectorPreview.Kind(item) : nil
        }

        private var hasPicture: Bool {
            localFile != nil || previewKind != nil
        }

        @ViewBuilder
        private var picture: some View {
            if let localFile {
                MacLocalFilePicture(url: localFile, item: item)
            } else if let previewKind {
                MacInspectorPreview(item: item, kind: previewKind, serverURL: serverURL)
            }
        }

        var body: some View {
            if hasPicture {
                VStack(alignment: .leading, spacing: .space16) {
                    picture
                        .frame(maxWidth: .infinity)
                        .frame(height: MacInspectorMetrics.pictureHeight)
                        .background(Color.macRow)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.pictureRadius, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            MacInspectorCloseButton(isOnPicture: true, action: onClose)
                                .padding(Metrics.pictureInset)
                        }
                        .overlay(alignment: .bottomLeading) {
                            if let badge {
                                Text(badge)
                                    .type(.caption(.semibold))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, .space8)
                                    .padding(.vertical, .space2)
                                    .background(Capsule()
                                        .fill(Color.black.opacity(MacInspectorMetrics.pictureScrimOpacity)))
                                    .padding(Metrics.pictureInset)
                            }
                        }
                    titles
                }
            } else {
                HStack(alignment: .top, spacing: .space16) {
                    icon
                    titles
                    MacInspectorCloseButton(action: onClose)
                }
            }
        }

        private var titles: some View {
            VStack(alignment: .leading, spacing: .space4) {
                Text(PersonalSpace.displayName(forSegment: item.name, isFirstSegment: item.path.isEmpty))
                    .type(.headline4)
                    .lineLimit(3)
                    .textSelection(.enabled)
                Text(subtitle)
                    .type(.body3(.regular), style: .secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, hasPicture ? .zero : .space4)
        }

        private var icon: some View {
            MacItemTile(kind: item.kind, isDirectory: item.isDirectory, size: Metrics.iconSize)
        }
    }

    private enum PreviewFixture {
        static let serverURL = URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")
        static let folder = FileItem(
            name: "Invoices",
            path: "Documents",
            dateModified: Date(),
            size: 0,
            kind: "directory"
        )
        static let file = FileItem(
            name: "report.zip",
            path: "Documents",
            dateModified: Date(),
            size: 2_400_000,
            kind: "zip"
        )
        static let image = FileItem(
            name: "portrait.jpg",
            path: "Photos",
            dateModified: Date(),
            size: 2_400_000,
            kind: "jpg"
        )
    }

    #Preview("Folder") {
        MacInspectorHeader(item: PreviewFixture.folder, subtitle: "Folder", serverURL: PreviewFixture.serverURL) {}
            .padding(MacInspectorMetrics.padding)
            .frame(width: MacInspectorMetrics.width)
            .background(Color.macCard)
    }

    #Preview("File") {
        MacInspectorHeader(item: PreviewFixture.file, subtitle: "ZIP · 2.4 MB", serverURL: PreviewFixture.serverURL) {}
            .padding(MacInspectorMetrics.padding)
            .frame(width: MacInspectorMetrics.width)
            .background(Color.macCard)
    }

    #Preview("Picture") {
        MacInspectorHeader(
            item: PreviewFixture.image,
            subtitle: "JPG · 2.4 MB",
            serverURL: PreviewFixture.serverURL,
            badge: "4000 × 6000"
        ) {}
            .padding(MacInspectorMetrics.padding)
            .frame(width: MacInspectorMetrics.width)
            .background(Color.macCard)
    }
#endif
