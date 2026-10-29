#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
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
        let serverURL: URL
        /// While the Permissions dialog is open; closing it reloads the section.
        var isEditingPermissions = false
        let onEditPermissions: () -> Void
        let onClose: () -> Void

        @Dependency(\.filesClient) private var filesClient
        /// Owner, group and mode come from the permissions endpoint, which metadata leaves out.
        @State private var permissions: FilePermissions?
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
                    permissionsSection
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .formStyle(.grouped)
            .frame(width: Metrics.width)
            .task(id: PermissionsLoad(path: item.id, isEditing: isEditingPermissions)) {
                permissions = nil
                let loaded = try? await filesClient.fetchPermissions(serverURL, item.id)
                guard !Task.isCancelled else { return }
                permissions = loaded
            }
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

        /// Like Finder's Sharing & Permissions: who owns it and the mode, with Edit opening the
        /// full Permissions dialog. Left out when the server doesn't report permissions.
        @ViewBuilder
        private var permissionsSection: some View {
            if let permissions {
                Section(L10n.Permissions.title) {
                    row(L10n.Permissions.fieldOwner, permissions.owner)
                    row(L10n.Permissions.fieldGroup, permissions.group)
                    row(L10n.Permissions.sectionMode, Self.modeString(permissions.mode))
                    HStack {
                        Spacer()
                        Button(L10n.Common.edit + "…", action: onEditPermissions)
                    }
                }
            }
        }

        /// `rw-r--r-- (644)` from a raw stat mode.
        private static func modeString(_ mode: Int) -> String {
            let bits = mode & 0o777
            let symbols = ["r", "w", "x"]
            let text = (0 ..< 9).map { index in
                bits & (1 << (8 - index)) != 0 ? symbols[index % 3] : "-"
            }.joined()
            return "\(text) (\(String(bits, radix: 8)))"
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

    private struct PermissionsLoad: Hashable {
        let path: String
        let isEditing: Bool
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
                        serverURL: screen.serverURL,
                        isEditingPermissions: screen.permissions != nil,
                        onEditPermissions: { screen.send(.permissionsTapped(item)) },
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
            metadata: nil, usage: nil, errorMessage: nil,
            serverURL: URL(fileURLWithPath: "/"), onEditPermissions: {}, onClose: {}
        )
    }

    #Preview("Loaded") {
        MacFileInspector(
            item: FileItem(name: "report.pdf", path: "Docs", dateModified: Date(), size: 2_400_000, kind: "pdf"),
            metadata: FileMetadata(
                path: "Docs/report.pdf", name: "report.pdf", kind: "pdf", size: 2_400_000,
                dateModified: Date(), dateCreated: Date().addingTimeInterval(-86_400)
            ),
            usage: nil, errorMessage: nil,
            serverURL: URL(fileURLWithPath: "/"), onEditPermissions: {}, onClose: {}
        )
    }

    #Preview("Error") {
        MacFileInspector(
            item: FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory"),
            metadata: nil, usage: nil, errorMessage: "Couldn't reach the server.",
            serverURL: URL(fileURLWithPath: "/"), onEditPermissions: {}, onClose: {}
        )
    }
#endif
