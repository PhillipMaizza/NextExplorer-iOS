#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    private enum Metrics {
        static let separator = " \u{00B7} "
    }

    /// Get Info on the Mac: a trailing side panel instead of a sheet, so it can stay open
    /// while the selection moves (`BrowseFeature` reloads it for each newly selected row). Laid
    /// out like Finder's inspector, in native grouped sections.
    struct MacFileInspector<More: View>: View {
        let item: FileItem
        let metadata: FileMetadata?
        let usage: StorageUsage?
        let errorMessage: String?
        let serverURL: URL
        /// While the Permissions dialog is open; closing it reloads the section.
        var isEditingPermissions = false
        var onEditPermissions: (() -> Void)?
        /// `nil` for a file: only folders can be favorites.
        var isFavorite: Bool?
        var onToggleFavorite: () -> Void = {}
        /// False until the favorites list has loaded, so a toggle cannot re add an existing favorite.
        var isFavoriteToggleEnabled = true
        /// This item's own share links; `nil` until the list has loaded.
        var shares: [Share]?
        /// Opens Create Share Link; `nil` without the right to share.
        var onShare: (() -> Void)?
        /// After a version is restored, so the listing picks up the restored file.
        var onRestored: () -> Void = {}
        var onOpen: (() -> Void)?
        var onRetry: () -> Void = {}
        var shouldShowThumbnails = true
        var showsMore = false
        let onClose: () -> Void
        @ViewBuilder let more: () -> More

        @Dependency(\.filesClient) private var filesClient
        /// Owner, group and mode come from the permissions endpoint, which metadata leaves out.
        @State private var permissions: FilePermissions?
        @State private var versions = MacVersionsModel()
        @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue
        @AppStorage(AppStorageKeys.includeTimeInDates) private var shouldIncludeTime = false

        private var dateFormat: DateDisplayFormat {
            DateDisplayFormat(rawValue: dateFormatRaw) ?? .system
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: MacInspectorMetrics.sectionSpacing) {
                    MacInspectorHeader(
                        item: item,
                        subtitle: headerSubtitle,
                        serverURL: serverURL,
                        badge: pictureBadge,
                        shouldShowThumbnails: shouldShowThumbnails,
                        onClose: onClose
                    )
                    MacInspectorQuickActions(actions: quickActions, showsMore: showsMore, more: more)
                    if let errorMessage {
                        VStack(alignment: .leading, spacing: .space8) {
                            Text(errorMessage).type(.body3(.regular), style: .error)
                            Button(L10n.Common.retry, action: onRetry)
                                .buttonStyle(.macDS(.secondary, size: .small))
                        }
                    } else if let metadata {
                        details(metadata)
                        if let shares {
                            MacInspectorSharingSection(shares: shares, serverURL: serverURL, onShare: onShare)
                        }
                        if let history = versions.history, history.isEnabled || !history.versions.isEmpty {
                            MacInspectorVersionsSection(model: versions, history: history, current: item)
                        }
                        if let permissions {
                            MacInspectorPermissionsSection(
                                permissions: permissions,
                                isDirectory: item.isDirectory,
                                onEdit: onEditPermissions
                            )
                        }
                    } else {
                        MacSpinner().frame(maxWidth: .infinity)
                    }
                }
                .padding(MacInspectorMetrics.padding)
            }
            .scrollIndicators(.never)
            .defaultScrollAnchor(.top)
            .id(item.id)
            .task(id: PermissionsLoad(path: item.id, isEditing: isEditingPermissions)) {
                permissions = nil
                try? await Task.sleep(for: MacInspectorMetrics.followDelay)
                guard !Task.isCancelled else { return }
                let loaded = try? await filesClient.fetchPermissions(serverURL, item.id)
                guard !Task.isCancelled else { return }
                permissions = loaded
            }
            .task(id: item.id) {
                versions.onFilesChanged = onRestored
                await versions.load(item: item, serverURL: serverURL, settle: MacInspectorMetrics.followDelay)
            }
            .modifier(MacVersionsDialogs(model: versions))
        }

        private var kindTitle: String {
            item.isDirectory ? L10n.FileInfo.navigationTitleFolder : item.kind.uppercased()
        }

        private var headerSubtitle: String {
            if item.isDirectory, let directory = metadata?.directory {
                let count = Int64(directory.fileCount + directory.dirCount)
                return [kindTitle, L10n.Shared.itemCount(count)].joined(separator: Metrics.separator)
            }
            return item.isDirectory
                ? kindTitle
                : [kindTitle, Self.bytes(item.size)].joined(separator: Metrics.separator)
        }

        private var dimensions: String? {
            if let width = metadata?.image?.width ?? metadata?.video?.width,
               let height = metadata?.image?.height ?? metadata?.video?.height
            {
                return "\(width) \u{00D7} \(height)"
            }
            return nil
        }

        private var duration: String? {
            metadata?.video?.duration.map { seconds in
                Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
            }
        }

        private var pictureBadge: String? {
            duration ?? dimensions
        }

        private var quickActions: [MacInspectorQuickAction] {
            var actions: [MacInspectorQuickAction] = []
            if let onOpen {
                actions.append(MacInspectorQuickAction(
                    icon: IconKit.openInApp,
                    title: L10n.Browse.open,
                    action: onOpen
                ))
            }
            if let onShare {
                actions.append(MacInspectorQuickAction(
                    icon: IconKit.link,
                    title: L10n.Common.share,
                    action: onShare
                ))
            }
            if let isFavorite {
                actions.append(MacInspectorQuickAction(
                    icon: isFavorite ? IconKit.starFill : IconKit.star,
                    title: L10n.FileInfo.quickFavorite,
                    isOn: isFavorite,
                    isEnabled: isFavoriteToggleEnabled,
                    action: onToggleFavorite
                ))
            }
            return actions
        }

        private func date(_ value: Date) -> String {
            dateFormat.string(from: value, includeTime: shouldIncludeTime)
        }

        @ViewBuilder
        private func details(_ metadata: FileMetadata) -> some View {
            MacInspectorGroup {
                if let directory = metadata.directory {
                    MacInspectorRow(
                        L10n.FileInfo.rowContains,
                        FolderContentSummary.text(folders: directory.dirCount, files: directory.fileCount)
                            ?? L10n.Shared.itemCount(Int64(0))
                    )
                    MacInspectorRow(L10n.FileInfo.rowSize, Self.bytes(directory.totalSize))
                } else {
                    MacInspectorRow(L10n.FileInfo.rowKind, kindTitle)
                    MacInspectorRow(L10n.FileInfo.rowSize, Self.bytes(metadata.size))
                }
                if let duration {
                    MacInspectorRow(L10n.FileInfo.rowDuration, duration)
                }
                if let dimensions {
                    MacInspectorRow(L10n.FileInfo.rowDimensions, dimensions)
                }
                MacInspectorRow(L10n.FileInfo.rowWhere, location, icon: IconKit.folderFill)
                MacInspectorRow(L10n.FileInfo.rowModified, date(metadata.dateModified))
                MacInspectorRow(L10n.FileInfo.rowCreated, date(metadata.dateCreated))
            }
            if metadata.directory?.isTruncated == true {
                Text(L10n.FileInfo.partialScan).type(.caption(.regular), style: .secondary)
            }
            if let image = metadata.image, image.cameraModel != nil || image.lensModel != nil
                || image.software != nil || image.dateTaken != nil || image.gps != nil
            {
                MacInspectorGroup {
                    if let model = image.cameraModel {
                        MacInspectorRow(
                            L10n.FileInfo.rowCamera,
                            [image.cameraMake, model].compactMap(\.self).joined(separator: " ")
                        )
                    }
                    if let lensModel = image.lensModel {
                        MacInspectorRow(L10n.FileInfo.rowLens, lensModel)
                    }
                    if let software = image.software {
                        MacInspectorRow(L10n.FileInfo.rowSoftware, software)
                    }
                    if let dateTaken = image.dateTaken {
                        MacInspectorRow(L10n.FileInfo.rowDateTaken, date(dateTaken))
                    }
                    if let gps = image.gps {
                        MacInspectorRow(L10n.FileInfo.rowLocation, String(format: "%.4f, %.4f", gps.lat, gps.lon))
                    }
                }
            }
            if let usage, usage.isMeaningful {
                VStack(alignment: .leading, spacing: .space8) {
                    MacInspectorSectionHeader(title: L10n.FileInfo.sectionServerDisk)
                    VStack(alignment: .leading, spacing: .space8) {
                        MacProgressBar(value: usage.fraction)
                        Text(L10n.FileInfo.diskFreeOf(Self.bytes(usage.free), Self.bytes(usage.capacity)))
                            .type(.caption(.regular), style: .secondary)
                    }
                    .padding(.space16)
                    .macGroupedRows()
                }
            }
        }

        private var location: String {
            MacInspectorLocation.title(parent: MacInspectorLocation.parent(of: item))
        }

        private static func bytes(_ count: Int64) -> String {
            FileSizeFormat.string(count)
        }
    }

    private struct SharesLoad: Hashable {
        let isOpen: Bool
        let revision: Int
    }

    private struct PermissionsLoad: Hashable {
        let path: String
        let isEditing: Bool
    }

    /// Get Info beside a Browse screen, as a plain side panel on each screen rather than
    /// SwiftUI's `.inspector` around the stack: wrapped around a `NavigationStack`, that stopped
    /// showing pushes past the third folder deep.
    struct MacBrowseInspector<More: View>: ViewModifier {
        let screen: StoreOf<BrowseFeature>
        let onOpen: (FileItem) -> Void
        let onShare: (FileItem) -> Void
        @ViewBuilder let more: (FileItem) -> More

        @State private var sharedLinks: [Share]?

        func body(content: Content) -> some View {
            content
                .macInspectorPane(
                    isOpen: screen.isInspectorOpen,
                    onOpen: screen.directoryPath.isEmpty ? nil : { screen.send(.infoSelectionTapped) },
                    onClose: { screen.send(.infoDismissed) }
                ) {
                    if let item = screen.infoItem {
                        inspector(item)
                    } else if screen.isInfoShowingSelection {
                        MacSelectionInspector(store: screen) { screen.send(.infoDismissed) }
                    }
                }
                .modifier(MacInspectorSharedLinks(
                    isOpen: screen.infoItem != nil,
                    serverURL: screen.serverURL,
                    links: $sharedLinks
                ))
        }

        private func inspector(_ item: FileItem) -> some View {
            MacFileInspector(
                item: item,
                metadata: screen.infoMetadata,
                usage: screen.infoUsage,
                errorMessage: screen.infoErrorMessage,
                serverURL: screen.serverURL,
                isEditingPermissions: screen.permissions != nil,
                onEditPermissions: { screen.send(.permissionsTapped(item)) },
                isFavorite: item.isDirectory ? screen.favoritePaths.contains(item.id) : nil,
                onToggleFavorite: { screen.send(.favoriteToggleButtonTapped(item)) },
                isFavoriteToggleEnabled: screen.hasLoadedFavorites,
                shares: MacInspectorSharedLinks.links(sharedLinks, for: item),
                onShare: (screen.access?.canShare ?? false) ? { onShare(item) } : nil,
                onRestored: { screen.send(.refreshButtonTapped) },
                onOpen: item.id == screen.directoryPath ? nil : { onOpen(item) },
                onRetry: { screen.send(.infoTapped(item)) },
                shouldShowThumbnails: screen.preferences.shouldShowThumbnails,
                showsMore: screen.items[id: item.id] != nil || item.id == screen.directoryPath,
                onClose: { screen.send(.infoDismissed) },
                more: { more(item) }
            )
        }
    }

    /// The caller's shared by me links, loaded once while an inspector is open rather than for
    /// every selection, reloaded when a link is created or edited anywhere in the app.
    struct MacInspectorSharedLinks: ViewModifier {
        let isOpen: Bool
        let serverURL: URL
        @Binding var links: [Share]?

        @Dependency(\.filesClient) private var filesClient
        @Shared(.inMemory(SharedFeature.revisionKey)) private var shareLinksRevision = 0

        func body(content: Content) -> some View {
            content.task(id: SharesLoad(isOpen: isOpen, revision: shareLinksRevision)) {
                guard isOpen else { return }
                let loaded = try? await filesClient.mySharedLinks(serverURL)
                guard !Task.isCancelled else { return }
                links = loaded
            }
        }

        /// Each item shows its own links; the server stores paths without outer slashes.
        static func links(_ all: [Share]?, for item: FileItem) -> [Share]? {
            let path = item.id.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return all?.filter { $0.sourcePath?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == path }
        }
    }

    #Preview("Loading") {
        MacFileInspector(
            item: FileItem(name: "report.pdf", path: "Docs", dateModified: Date(), size: 2_400_000, kind: "pdf"),
            metadata: nil, usage: nil, errorMessage: nil,
            serverURL: URL(fileURLWithPath: "/"), onEditPermissions: {}, onClose: {}, more: { EmptyView() }
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
            serverURL: URL(fileURLWithPath: "/"), onEditPermissions: {}, onClose: {}, more: { EmptyView() }
        )
    }

    #Preview("Error") {
        MacFileInspector(
            item: FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory"),
            metadata: nil, usage: nil, errorMessage: "Couldn't reach the server.",
            serverURL: URL(fileURLWithPath: "/"), onEditPermissions: {}, onClose: {}, more: { EmptyView() }
        )
    }
#endif
