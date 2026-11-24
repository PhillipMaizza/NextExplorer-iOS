#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    struct ArchivePeekGrid: View {
        let entries: [ArchiveListingEntry]
        var thumbnails: ArchiveThumbnailLoader?
        let onOpen: (ArchiveListingEntry) -> Void

        var body: some View {
            ScrollView {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: .space16),
                        count: MacPeekMetrics.columns
                    ),
                    spacing: .space16
                ) {
                    ForEach(entries) { entry in
                        Button {
                            onOpen(entry)
                        } label: {
                            ArchivePeekTile(entry: entry, thumbnails: thumbnails)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.space24)
            }
        }
    }

    struct ArchivePeekTile: View {
        let entry: ArchiveListingEntry
        var thumbnails: ArchiveThumbnailLoader?

        @State private var thumbnail: CGImage?

        var body: some View {
            VStack(spacing: .space8) {
                RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                    .fill(Color.macSegment)
                    .aspectRatio(MacPeekMetrics.tileAspect, contentMode: .fit)
                    .overlay {
                        if let thumbnail {
                            Image(decorative: thumbnail, scale: 1)
                                .resizable()
                                .scaledToFill()
                        } else if entry.isEncrypted {
                            IconKit.lock
                                .font(.system(size: .iconMedium))
                                .foregroundStyle(Color.secondaryText)
                        } else {
                            MacItemTile(kind: entry.kind, isDirectory: entry.isDirectory, size: MacPeekMetrics.iconSize)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: .radiusControl, style: .continuous))
                    .task(id: entry.path) { await loadThumbnail() }
                VStack(spacing: .space2) {
                    Text(entry.name)
                        .type(.body3(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(ArchivePeekText.detail(entry))
                        .type(.caption(.regular), style: .secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }

        private func loadThumbnail() async {
            guard let thumbnails, ArchiveThumbnailLoader.wantsThumbnail(entry) else { return }
            let image = await thumbnails.image(for: entry)
            guard !Task.isCancelled else { return }
            thumbnail = image
        }
    }

    #Preview("Archive grid") {
        ArchivePeekGrid(
            entries: [
                ArchiveListingEntry(path: "Photos", name: "Photos", isDirectory: true, size: nil),
                ArchiveListingEntry(path: "cover.jpg", name: "cover.jpg", isDirectory: false, size: 820_000),
                ArchiveListingEntry(
                    path: "Guidelines.pdf",
                    name: "Guidelines.pdf",
                    isDirectory: false,
                    size: 2_400_000
                ),
                ArchiveListingEntry(
                    path: "Contract.pdf",
                    name: "Contract.pdf",
                    isDirectory: false,
                    size: 640_000,
                    isEncrypted: true
                ),
                ArchiveListingEntry(path: "README.md", name: "README.md", isDirectory: false, size: 3_000),
            ],
            onOpen: { _ in }
        )
        .frame(width: MacPeekMetrics.previewWidth, height: MacPeekMetrics.previewHeight)
        .background(Color.macCard)
    }
#endif
