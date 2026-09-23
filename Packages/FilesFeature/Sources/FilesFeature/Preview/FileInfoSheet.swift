import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let contentSpacing: CGFloat = .space24
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
    var usage: StorageUsage?
    let errorMessage: String?
    let onDismiss: () -> Void

    var body: some View {
        DSDynamicHeightSheet {
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
                FileInfoDetails(metadata: metadata, usage: usage)
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Constants.topPadding)
        .padding(.bottom, Constants.bottomPadding)
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
