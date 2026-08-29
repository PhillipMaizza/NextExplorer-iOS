import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let contentSpacing: CGFloat = .space24
    static let cardSpacing: CGFloat = .space12
    static let cardPadding: CGFloat = .space16
    static let cardVerticalPadding: CGFloat = .space16
    static let rowVerticalPadding: CGFloat = .space8
    static let rowMinimumGap: CGFloat = .space32
    static let horizontalPadding: CGFloat = .space24
    static let topPadding: CGFloat = .space24
    static let bottomPadding: CGFloat = .space24
}

/// "Get Info" sheet for a single file/folder: everything `GET /api/metadata/*` actually
/// returns (`backend/src/routes/metadata.js`) — there's no owner/group/permissions data
/// anywhere in that response, so this deliberately doesn't show fields the real server
/// can't back up.
///
/// Deliberately presented only once the fetch has actually resolved (success or failure) —
/// see `BrowseContentView.InfoSheetPhase` and `FileInfoLoadingSheet`, which is shown instead
/// while the fetch is still in flight.
struct FileInfoSheet: View {
    let item: FileItem
    let metadata: FileMetadata?
    /// Server disk figures for a directory, when the server reported them.
    var usage: StorageUsage? = nil
    let errorMessage: String?
    let onDismiss: () -> Void

    @AppStorage("dateDisplayFormat") private var dateFormatRaw = DateDisplayFormat.system.rawValue
    @AppStorage("includeTimeInDates") private var includeTime = false

    private var dateFormat: DateDisplayFormat { DateDisplayFormat(rawValue: dateFormatRaw) ?? .system }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter
    }()

    var body: some View {
        DynamicHeightSheet {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Constants.contentSpacing) {
            DSSheetHeader(
                icon: item.isDirectory ? IconKit.folderFill : IconKit.document,
                title: item.name,
                closeAccessibilityLabel: L10n.Common.close,
                onClose: onDismiss
            )

            if let errorMessage {
                DSErrorCard(errorMessage)
            } else if let metadata {
                metadataSections(for: metadata)
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Constants.topPadding)
        .padding(.bottom, Constants.bottomPadding)
    }

    @ViewBuilder
    private func metadataSections(for metadata: FileMetadata) -> some View {
        VStack(alignment: .leading, spacing: Constants.cardSpacing) {
            card {
                row(L10n.FileInfo.rowKind, kindTitle(for: metadata))
                row(L10n.FileInfo.rowSize, Self.byteFormatter.string(fromByteCount: metadata.size))
                row(L10n.FileInfo.rowLocation, metadata.path)
                row(L10n.FileInfo.rowDateModified, dateFormat.string(from: metadata.dateModified, includeTime: includeTime))
                row(L10n.FileInfo.rowDateCreated, dateFormat.string(from: metadata.dateCreated, includeTime: includeTime))
            }

            if let directory = metadata.directory {
                card {
                    row(L10n.FileInfo.rowFiles, "\(directory.fileCount)")
                    row(L10n.FileInfo.rowFolders, "\(directory.dirCount)")
                    row(L10n.FileInfo.rowTotalSize, Self.byteFormatter.string(fromByteCount: directory.totalSize))
                    if directory.truncated {
                        Text(L10n.FileInfo.partialScan)
                            .type(.body3(.regular), style: .tertiary)
                            .padding(.top, .space4)
                    }
                }
            }

            if let usage, usage.isMeaningful {
                card {
                    DSFieldLabel(L10n.FileInfo.sectionServerDisk)
                    DSUsageBar(fraction: usage.fraction)
                        .padding(.vertical, .space4)
                    Text(L10n.FileInfo.diskFreeOf(
                        Self.byteFormatter.string(fromByteCount: usage.free),
                        Self.byteFormatter.string(fromByteCount: usage.capacity)
                    ))
                    .type(.body3(.regular), style: .secondary)
                }
            }

            if let image = metadata.image {
                card {
                    if let width = image.width, let height = image.height {
                        row(L10n.FileInfo.rowDimensions, "\(width) × \(height)")
                    }
                    if let make = image.cameraMake, let model = image.cameraModel {
                        row(L10n.FileInfo.rowCamera, "\(make) \(model)")
                    } else if let model = image.cameraModel {
                        row(L10n.FileInfo.rowCamera, model)
                    }
                    if let lensModel = image.lensModel {
                        row(L10n.FileInfo.rowLens, lensModel)
                    }
                    if let dateTaken = image.dateTaken {
                        row(L10n.FileInfo.rowDateTaken, dateFormat.string(from: dateTaken, includeTime: includeTime))
                    }
                    if let gps = image.gps {
                        row(L10n.FileInfo.rowLocation, String(format: "%.4f, %.4f", gps.lat, gps.lon))
                    }
                }
            }

            if let video = metadata.video {
                card {
                    if let width = video.width, let height = video.height {
                        row(L10n.FileInfo.rowDimensions, "\(width) × \(height)")
                    }
                    if let duration = video.duration {
                        row(L10n.FileInfo.rowDuration, Self.durationFormatter.string(from: duration) ?? "-")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: .space8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Constants.cardPadding)
        .padding(.vertical, Constants.cardVerticalPadding)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: .radiusCard))
    }

    private func kindTitle(for metadata: FileMetadata) -> String {
        metadata.isDirectory ? L10n.FileInfo.navigationTitleFolder : metadata.kind.uppercased()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: Constants.rowMinimumGap) {
            Text(label)
                .type(.body2(.regular), style: .secondary)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: Constants.rowMinimumGap)
            Text(value)
                .type(.body2(.regular), style: .primary(for: .label))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, Constants.rowVerticalPadding)
    }
}

#Preview("Folder") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            FileInfoSheet(
                item: FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory"),
                metadata: FileMetadata(
                    path: "Photos",
                    name: "Photos",
                    kind: "directory",
                    size: 4_096,
                    dateModified: Date(),
                    dateCreated: Date().addingTimeInterval(-86_400 * 30),
                    directory: FileMetadata.DirectorySummary(totalSize: 10_485_760, fileCount: 42, dirCount: 3, truncated: false)
                ),
                errorMessage: nil,
                onDismiss: {}
            )
        }
}

#Preview("Folder with server disk") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            FileInfoSheet(
                item: FileItem(name: "Media", path: "", dateModified: Date(), size: 0, kind: "directory"),
                metadata: FileMetadata(
                    path: "Media",
                    name: "Media",
                    kind: "directory",
                    size: 4_096,
                    dateModified: Date(),
                    dateCreated: Date().addingTimeInterval(-86_400 * 120),
                    directory: FileMetadata.DirectorySummary(totalSize: 41_000_000_000, fileCount: 1_200, dirCount: 60, truncated: false)
                ),
                usage: StorageUsage(path: "Media", size: 41_000_000_000, free: 59_000_000_000, total: 100_000_000_000),
                errorMessage: nil,
                onDismiss: {}
            )
        }
}

#Preview("Folder with server disk — filling up") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            FileInfoSheet(
                item: FileItem(name: "Projects", path: "", dateModified: Date(), size: 0, kind: "directory"),
                metadata: FileMetadata(
                    path: "Projects", name: "Projects", kind: "directory", size: 4_096,
                    dateModified: Date(), dateCreated: Date(),
                    directory: FileMetadata.DirectorySummary(totalSize: 78_000_000_000, fileCount: 320, dirCount: 40, truncated: false)
                ),
                usage: StorageUsage(path: "Projects", size: 78_000_000_000, free: 22_000_000_000, total: 100_000_000_000),
                errorMessage: nil,
                onDismiss: {}
            )
        }
}

#Preview("Folder with server disk — nearly full") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            FileInfoSheet(
                item: FileItem(name: "Backups", path: "", dateModified: Date(), size: 0, kind: "directory"),
                metadata: FileMetadata(
                    path: "Backups", name: "Backups", kind: "directory", size: 4_096,
                    dateModified: Date(), dateCreated: Date(),
                    directory: FileMetadata.DirectorySummary(totalSize: 94_000_000_000, fileCount: 8, dirCount: 0, truncated: false)
                ),
                usage: StorageUsage(path: "Backups", size: 94_000_000_000, free: 6_000_000_000, total: 100_000_000_000),
                errorMessage: nil,
                onDismiss: {}
            )
        }
}

#Preview("Image with EXIF") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            FileInfoSheet(
                item: FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 2_400_000, kind: "jpg"),
                metadata: FileMetadata(
                    path: "Photos/vacation.jpg",
                    name: "vacation.jpg",
                    kind: "jpg",
                    size: 2_400_000,
                    dateModified: Date(),
                    dateCreated: Date(),
                    image: FileMetadata.ImageMetadata(
                        width: 4032, height: 3024, cameraMake: "Apple", cameraModel: "iPhone 15 Pro",
                        dateTaken: Date(), gps: FileMetadata.ImageMetadata.GPSCoordinate(lat: 37.3349, lon: -122.0090)
                    )
                ),
                errorMessage: nil,
                onDismiss: {}
            )
        }
}

#Preview("Video") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            FileInfoSheet(
                item: FileItem(name: "clip.mp4", path: "", dateModified: Date(), size: 9_000_000, kind: "mp4"),
                metadata: FileMetadata(
                    path: "Videos/clip.mp4",
                    name: "clip.mp4",
                    kind: "mp4",
                    size: 9_000_000,
                    dateModified: Date(),
                    dateCreated: Date(),
                    video: FileMetadata.VideoMetadata(width: 1920, height: 1080, duration: 125)
                ),
                errorMessage: nil,
                onDismiss: {}
            )
        }
}

#Preview("Plain file") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            FileInfoSheet(
                item: FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 128, kind: "txt"),
                metadata: FileMetadata(path: "notes.txt", name: "notes.txt", kind: "txt", size: 128, dateModified: Date(), dateCreated: Date()),
                errorMessage: nil,
                onDismiss: {}
            )
        }
}

#Preview("Error") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            FileInfoSheet(
                item: FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 128, kind: "txt"),
                metadata: nil,
                errorMessage: "Couldn't reach the server.",
                onDismiss: {}
            )
        }
}
