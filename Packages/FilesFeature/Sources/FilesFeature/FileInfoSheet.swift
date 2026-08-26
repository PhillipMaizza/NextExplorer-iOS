import CoreModels
import DesignSystem
import SwiftUI

private enum Constants {
    static let headerIconSize: CGFloat = .iconMedium
    static let closeIconSize: CGFloat = .iconXSmall
    static let closeButtonPadding: CGFloat = .space8
    static let contentSpacing: CGFloat = .space16
    static let rowVerticalPadding: CGFloat = .space8
    static let horizontalPadding: CGFloat = .space24
    static let topPadding: CGFloat = .space24
    static let bottomPadding: CGFloat = .space24
    static let loadingVerticalPadding: CGFloat = .space24
}

/// "Get Info" sheet for a single file/folder: everything `GET /api/metadata/*` actually
/// returns (`backend/src/routes/metadata.js`) — there's no owner/group/permissions data
/// anywhere in that response, so this deliberately doesn't show fields the real server
/// can't back up.
struct FileInfoSheet: View {
    let item: FileItem
    let metadata: FileMetadata?
    let isLoading: Bool
    let errorMessage: String?
    let onDismiss: () -> Void

    @AppStorage("dateDisplayFormat") private var dateFormatRaw = DateDisplayFormat.system.rawValue

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
        // Re-measures once loading finishes: unlike this app's other sheets, this one's
        // content genuinely changes shape (a small spinner, then the full metadata layout),
        // so the height can't just lock on the first (loading) measurement.
        DynamicHeightSheet(resetKey: isLoading) {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Constants.contentSpacing) {
            header

            Text(item.name).type(.headline3, style: .primary(for: .label)).lineLimit(2)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Constants.loadingVerticalPadding)
            } else if let errorMessage {
                Text(errorMessage).type(.body2(.regular), style: .error)
            } else if let metadata {
                metadataSections(for: metadata)
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Constants.topPadding)
        .padding(.bottom, Constants.bottomPadding)
    }

    private var header: some View {
        HStack {
            (item.isDirectory ? IconKit.folderFill : IconKit.document)
                .resizable()
                .foregroundStyle(item.isDirectory ? Color.accent : Color.secondaryDS)
                .frame(width: Constants.headerIconSize, height: Constants.headerIconSize)

            Spacer()

            Button(action: onDismiss) {
                IconKit.xmark
                    .resizable()
                    .foregroundStyle(Color.primaryDS)
                    .frame(width: Constants.closeIconSize, height: Constants.closeIconSize)
                    .padding(Constants.closeButtonPadding)
                    .background(Circle().fill(Color.backgroundSecondary))
            }
        }
    }

    @ViewBuilder
    private func metadataSections(for metadata: FileMetadata) -> some View {
        VStack(spacing: 0) {
            row("Kind", kindTitle(for: metadata))
            row("Size", Self.byteFormatter.string(fromByteCount: metadata.size))
            row("Location", metadata.path)
            row("Date Modified", dateFormat.string(from: metadata.dateModified))
            row("Date Created", dateFormat.string(from: metadata.dateCreated))
        }

        if let directory = metadata.directory {
            Divider()
            VStack(spacing: 0) {
                row("Files", "\(directory.fileCount)")
                row("Folders", "\(directory.dirCount)")
                row("Total Size", Self.byteFormatter.string(fromByteCount: directory.totalSize))
                if directory.truncated {
                    Text("Counted a partial scan — this folder is very large.")
                        .type(.body3(.regular), style: .tertiary)
                        .padding(.top, .space4)
                }
            }
        }

        if let image = metadata.image {
            Divider()
            VStack(spacing: 0) {
                if let width = image.width, let height = image.height {
                    row("Dimensions", "\(width) × \(height)")
                }
                if let make = image.cameraMake, let model = image.cameraModel {
                    row("Camera", "\(make) \(model)")
                } else if let model = image.cameraModel {
                    row("Camera", model)
                }
                if let lensModel = image.lensModel {
                    row("Lens", lensModel)
                }
                if let dateTaken = image.dateTaken {
                    row("Date Taken", dateFormat.string(from: dateTaken))
                }
                if let gps = image.gps {
                    row("Location", String(format: "%.4f, %.4f", gps.lat, gps.lon))
                }
            }
        }

        if let video = metadata.video {
            Divider()
            VStack(spacing: 0) {
                if let width = video.width, let height = video.height {
                    row("Dimensions", "\(width) × \(height)")
                }
                if let duration = video.duration {
                    row("Duration", Self.durationFormatter.string(from: duration) ?? "-")
                }
            }
        }
    }

    private func kindTitle(for metadata: FileMetadata) -> String {
        metadata.isDirectory ? "Folder" : metadata.kind.uppercased()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).type(.body2(.regular), style: .secondary)
            Spacer()
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
                isLoading: false,
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
                isLoading: false,
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
                isLoading: false,
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
                isLoading: false,
                errorMessage: nil,
                onDismiss: {}
            )
        }
}

#Preview("Loading") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            FileInfoSheet(
                item: FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 128, kind: "txt"),
                metadata: nil,
                isLoading: true,
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
                isLoading: false,
                errorMessage: "Couldn't reach the server.",
                onDismiss: {}
            )
        }
}
