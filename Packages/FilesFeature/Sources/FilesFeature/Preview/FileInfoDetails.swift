import AppStorageKeys
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let cardSpacing: CGFloat = .space12
    static let cardPadding: CGFloat = .space16
    static let cardVerticalPadding: CGFloat = .space16
    static let rowVerticalPadding: CGFloat = .space8
    static let rowMinimumGap: CGFloat = .space32
}

/// The body of "Get Info": everything `GET /api/metadata/*` returns, as grouped cards. Shared by
/// the iOS sheet (`FileInfoSheet`) and the Mac inspector (`MacFileInspector`).
struct FileInfoDetails: View {
    let metadata: FileMetadata
    /// Server disk figures for a directory, when the server reported them.
    var usage: StorageUsage?
    /// Label above value instead of side by side: the narrow Mac inspector column has no room
    /// for both on one line.
    var stacksValues = false

    @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue
    @AppStorage(AppStorageKeys.includeTimeInDates) private var includeTime = false

    private var dateFormat: DateDisplayFormat {
        DateDisplayFormat(rawValue: dateFormatRaw) ?? .system
    }

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

    @ViewBuilder
    var body: some View {
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
                    DSFieldLabel(L10n.FileInfo.sectionServerDisk, uppercased: false)
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
    private func card(@ViewBuilder _ content: () -> some View) -> some View {
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

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        if stacksValues {
            VStack(alignment: .leading, spacing: .space2) {
                Text(label)
                    .type(.body3(.regular), style: .secondary)
                Text(value)
                    .type(.body2(.regular), style: .primaryOnSurface)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Constants.rowVerticalPadding / 2)
        } else {
            sideBySideRow(label, value)
        }
    }

    private func sideBySideRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: Constants.rowMinimumGap) {
            Text(label)
                .type(.body2(.regular), style: .secondary)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: Constants.rowMinimumGap)
            Text(value)
                .type(.body2(.regular), style: .primaryOnSurface)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, Constants.rowVerticalPadding)
    }
}

#Preview("File") {
    ScrollView {
        FileInfoDetails(metadata: FileMetadata(
            path: "Docs/report.pdf",
            name: "report.pdf",
            kind: "pdf",
            size: 2_400_000,
            dateModified: Date(),
            dateCreated: Date().addingTimeInterval(-86_400 * 7)
        ))
        .padding()
    }
}

#Preview("Folder with disk usage") {
    ScrollView {
        FileInfoDetails(
            metadata: FileMetadata(
                path: "Media",
                name: "Media",
                kind: "directory",
                size: 4_096,
                dateModified: Date(),
                dateCreated: Date().addingTimeInterval(-86_400 * 120),
                directory: FileMetadata.DirectorySummary(totalSize: 41_000_000_000, fileCount: 1_200, dirCount: 60, truncated: true)
            ),
            usage: StorageUsage(path: "Media", size: 41_000_000_000, free: 59_000_000_000, total: 100_000_000_000)
        )
        .padding()
    }
}
