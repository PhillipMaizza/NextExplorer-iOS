#if os(iOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let iconSize: CGFloat = .iconLarge
        static let lockSize: CGFloat = .iconMedium
        static let tileAspect: CGFloat = 1
    }

    struct ArchiveTile: View {
        let entry: ArchiveListingEntry
        var thumbnails: ArchiveThumbnailLoader?
        var isOpening = false

        @State private var thumbnail: CGImage?

        var body: some View {
            VStack(spacing: .space8) {
                RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                    .fill(Color.backgroundSecondary)
                    .aspectRatio(Metrics.tileAspect, contentMode: .fit)
                    .overlay { artwork }
                    .clipShape(RoundedRectangle(cornerRadius: .radiusControl, style: .continuous))
                    .task(id: entry.path) { await loadThumbnail() }
                VStack(spacing: .space2) {
                    Text(entry.name)
                        .type(.body3(.semibold), style: .primaryOnSurface)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let size = entry.size, !entry.isDirectory {
                        Text(FileSizeFormat.string(size))
                            .type(.caption(.regular), style: .secondary)
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }

        @ViewBuilder
        private var artwork: some View {
            if isOpening {
                DSSpinner()
            } else if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else if entry.isEncrypted {
                IconKit.lock
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Metrics.lockSize, height: Metrics.lockSize)
            } else if entry.isDirectory {
                IconKit.folderFill
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.accent)
                    .frame(width: Metrics.iconSize, height: Metrics.iconSize)
            } else {
                FileTypeIcon(kind: entry.kind)
                    .frame(width: Metrics.iconSize, height: Metrics.iconSize)
            }
        }

        private func loadThumbnail() async {
            guard let thumbnails, ArchiveThumbnailLoader.wantsThumbnail(entry) else { return }
            let image = await thumbnails.image(for: entry)
            guard !Task.isCancelled else { return }
            thumbnail = image
        }
    }

    #Preview("Tiles") {
        FileGrid {
            ArchiveTile(entry: ArchiveListingEntry(path: "Photos", name: "Photos", isDirectory: true, size: nil))
            ArchiveTile(entry: ArchiveListingEntry(
                path: "plan.pdf",
                name: "plan.pdf",
                isDirectory: false,
                size: 2_400_000
            ))
            ArchiveTile(
                entry: ArchiveListingEntry(
                    path: "c.pdf",
                    name: "Contract.pdf",
                    isDirectory: false,
                    size: 640_000,
                    isEncrypted: true
                )
            )
            ArchiveTile(
                entry: ArchiveListingEntry(path: "notes.txt", name: "notes.txt", isDirectory: false, size: 3_000),
                isOpening: true
            )
        }
        .padding(.space16)
    }
#endif
