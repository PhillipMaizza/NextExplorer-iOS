#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let iconSize: CGFloat = .size44
        static let width: CGFloat = 300
        static let slideDuration: Double = 0.2
    }

    /// Get Info on the Mac: a trailing side panel instead of a sheet, so it can stay open
    /// while the selection moves (`BrowseFeature` reloads it for each newly selected row). Laid
    /// out like Finder's inspector, in native grouped sections.
    struct MacFileInspector: View {
        let item: FileItem
        let metadata: FileMetadata?
        let usage: StorageUsage?
        let errorMessage: String?
        let onClose: () -> Void

        @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue
        @AppStorage(AppStorageKeys.includeTimeInDates) private var includeTime = false

        private var dateFormat: DateDisplayFormat {
            DateDisplayFormat(rawValue: dateFormatRaw) ?? .system
        }

        var body: some View {
            Form {
                Section {
                    header
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Color.negativeText)
                } else if let metadata {
                    details(metadata)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .formStyle(.grouped)
            .frame(width: Metrics.width)
        }

        private var header: some View {
            HStack(alignment: .top, spacing: .space12) {
                Group {
                    if item.isDirectory {
                        Image(systemName: "folder.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(Color.accent)
                    } else {
                        FileTypeIcon(kind: item.kind)
                    }
                }
                .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                Text(item.name)
                    .font(.headline)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Close lives in the panel, not the window toolbar, so the inspector never adds
                // toolbar items of its own.
                Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabelWithTooltip(L10n.Common.close)
                    .keyboardShortcut(.cancelAction)
            }
        }

        @ViewBuilder
        private func details(_ metadata: FileMetadata) -> some View {
            Section {
                row(L10n.FileInfo.rowKind, metadata.isDirectory ? L10n.FileInfo.navigationTitleFolder : metadata.kind.uppercased())
                row(L10n.FileInfo.rowSize, Self.bytes(metadata.size))
                row(L10n.FileInfo.rowLocation, metadata.path)
                row(L10n.FileInfo.rowDateModified, dateFormat.string(from: metadata.dateModified, includeTime: includeTime))
                row(L10n.FileInfo.rowDateCreated, dateFormat.string(from: metadata.dateCreated, includeTime: includeTime))
            }
            if let directory = metadata.directory {
                Section {
                    row(L10n.FileInfo.rowFiles, "\(directory.fileCount)")
                    row(L10n.FileInfo.rowFolders, "\(directory.dirCount)")
                    row(L10n.FileInfo.rowTotalSize, Self.bytes(directory.totalSize))
                } footer: {
                    if directory.truncated {
                        Text(L10n.FileInfo.partialScan).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            if let usage, usage.isMeaningful {
                Section(L10n.FileInfo.sectionServerDisk) {
                    VStack(alignment: .leading, spacing: .space4) {
                        ProgressView(value: usage.fraction)
                        Text(L10n.FileInfo.diskFreeOf(Self.bytes(usage.free), Self.bytes(usage.capacity)))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let image = metadata.image {
                Section {
                    if let width = image.width, let height = image.height {
                        row(L10n.FileInfo.rowDimensions, "\(width) × \(height)")
                    }
                    if let model = image.cameraModel {
                        row(L10n.FileInfo.rowCamera, [image.cameraMake, model].compactMap(\.self).joined(separator: " "))
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
                Section {
                    if let width = video.width, let height = video.height {
                        row(L10n.FileInfo.rowDimensions, "\(width) × \(height)")
                    }
                    if let duration = video.duration {
                        row(L10n.FileInfo.rowDuration, Self.durationFormatter.string(from: duration) ?? "-")
                    }
                }
            }
        }

        private func row(_ label: String, _ value: String) -> some View {
            LabeledContent(label) {
                Text(value)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }

        private static func bytes(_ count: Int64) -> String {
            SettingsFormat.byteFormatter.string(fromByteCount: count)
        }

        private static let durationFormatter: DateComponentsFormatter = {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute, .second]
            formatter.unitsStyle = .positional
            formatter.zeroFormattingBehavior = .dropLeading
            return formatter
        }()
    }

    /// Get Info beside a Browse screen, as a plain side panel on each screen rather than
    /// SwiftUI's `.inspector` around the stack: wrapped around a `NavigationStack`, that stopped
    /// showing pushes past the third folder deep.
    struct MacBrowseInspector: ViewModifier {
        let screen: StoreOf<BrowseFeature>

        func body(content: Content) -> some View {
            HStack(spacing: 0) {
                content
                if let item = screen.infoItem {
                    Divider()
                    MacFileInspector(
                        item: item,
                        metadata: screen.infoMetadata,
                        usage: screen.infoUsage,
                        errorMessage: screen.infoErrorMessage,
                        onClose: { screen.send(.infoDismissed) }
                    )
                    .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: Metrics.slideDuration), value: screen.infoItem == nil)
        }
    }

    #Preview("Loading") {
        MacFileInspector(
            item: FileItem(name: "report.pdf", path: "Docs", dateModified: Date(), size: 2_400_000, kind: "pdf"),
            metadata: nil, usage: nil, errorMessage: nil, onClose: {}
        )
    }

    #Preview("Loaded") {
        MacFileInspector(
            item: FileItem(name: "report.pdf", path: "Docs", dateModified: Date(), size: 2_400_000, kind: "pdf"),
            metadata: FileMetadata(
                path: "Docs/report.pdf", name: "report.pdf", kind: "pdf", size: 2_400_000,
                dateModified: Date(), dateCreated: Date().addingTimeInterval(-86_400)
            ),
            usage: nil, errorMessage: nil, onClose: {}
        )
    }

    #Preview("Error") {
        MacFileInspector(
            item: FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory"),
            metadata: nil, usage: nil, errorMessage: "Couldn't reach the server.", onClose: {}
        )
    }
#endif
