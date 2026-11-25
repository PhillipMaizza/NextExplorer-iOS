import ComposableArchitecture
import CoreModels
import FilesClient
import SwiftUI

#if os(macOS)
    import AppStorageKeys
    import DesignSystem
    import Localization

    extension EnvironmentValues {
        @Entry var macOfflineSelection: Binding<Set<MacOfflineTableRow.ID>>?
    }

    struct MacOfflineInspector: View {
        let row: MacOfflineTableRow
        let serverURL: URL
        let onOpen: () -> Void
        let onRemove: () -> Void
        let onClose: () -> Void

        @Dependency(\.offlineFileStore) private var offlineFileStore
        @State private var localFile: URL?
        @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue
        @AppStorage(AppStorageKeys.includeTimeInDates) private var shouldIncludeTime = false

        private var item: FileItem {
            switch row {
            case let .pinned(usage):
                let path = usage.root.path as NSString
                return FileItem(
                    name: usage.displayName,
                    path: usage.parentPath,
                    dateModified: usage.copy?.dateModified ?? FileItem.unknownDate,
                    size: usage.sizeBytes,
                    kind: usage.root.isDirectory ? FileItem.directoryKind : path.pathExtension.lowercased()
                )
            case let .saved(download):
                return FileItem(
                    name: download.fileName,
                    path: "",
                    dateModified: download.modifiedDate,
                    size: download.size,
                    kind: (download.fileName as NSString).pathExtension.lowercased()
                )
            }
        }

        private var subtitle: String {
            let kind = item.isDirectory ? L10n.FileInfo.navigationTitleFolder : item.kind.uppercased()
            return [kind, FileSizeFormat.string(item.size)].joined(separator: MacPeekMetrics.separator)
        }

        private var location: String {
            switch row {
            case let .pinned(usage): MacInspectorLocation.trail(parent: usage.parentPath)
            case .saved: L10n.Offline.sectionSavedEarlier
            }
        }

        private var modified: String? {
            guard !item.isDirectory, item.hasKnownDate else { return nil }
            let format = DateDisplayFormat(rawValue: dateFormatRaw) ?? .system
            return format.string(from: item.dateModified, includeTime: shouldIncludeTime)
        }

        private var quickActions: [MacInspectorQuickAction] {
            [
                MacInspectorQuickAction(id: .open, icon: IconKit.openInApp, title: L10n.Browse.open, action: onOpen),
                MacInspectorQuickAction(
                    id: .remove,
                    icon: IconKit.delete,
                    title: row.saved == nil ? L10n.Common.remove : L10n.Common.delete,
                    action: onRemove
                ),
            ]
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: MacInspectorMetrics.sectionSpacing) {
                    MacInspectorHeader(
                        item: item,
                        subtitle: subtitle,
                        serverURL: serverURL,
                        localFile: localFile,
                        onClose: onClose
                    )
                    MacInspectorQuickActions(actions: quickActions, showsMore: localFile != nil && !item.isDirectory) {
                        if let localFile {
                            MacLocalFilePanelRows { localFile }
                        }
                    }
                    MacInspectorGroup {
                        MacInspectorRow(L10n.FileInfo.rowSize, FileSizeFormat.string(item.size))
                        MacInspectorRow(L10n.FileInfo.rowWhere, location, icon: IconKit.folderFill)
                        if let modified {
                            MacInspectorRow(L10n.FileInfo.rowModified, modified)
                        }
                    }
                }
                .padding(MacInspectorMetrics.padding)
            }
            .scrollIndicators(.never)
            .defaultScrollAnchor(.top)
            .id(row.id)
            .task(id: row.id) {
                localFile = nil
                let item = item
                let row = row
                let store = offlineFileStore
                let resolved = await Task.detached(priority: .userInitiated) { () -> URL? in
                    switch row {
                    case .pinned where item.isDirectory: nil
                    case .pinned: store.localURLIgnoringStaleness(item)
                    case let .saved(download): FileManager.default.fileExists(atPath: download.url.path)
                        ? download.url
                        : nil
                    }
                }.value
                guard !Task.isCancelled else { return }
                localFile = resolved
            }
        }
    }

    struct MacOfflineInspectorPane: ViewModifier {
        let store: StoreOf<OfflineTabFeature>
        let offlineStore: StoreOf<OfflineManageFeature>
        let pinned: [OfflinePinnedRootUsage]
        let onPreview: (LocalDownload) -> Void

        @State private var selection: Set<MacOfflineTableRow.ID> = []

        private var row: MacOfflineTableRow? {
            guard selection.count == 1, let id = selection.first else { return nil }
            let rows = pinned.map(MacOfflineTableRow.pinned) + store.displayedDownloads.map(MacOfflineTableRow.saved)
            return rows.first { $0.id == id }
        }

        func body(content: Content) -> some View {
            let row = row
            content
                .environment(\.macOfflineSelection, $selection)
                .macInspectorPane(isOpen: isOpen(row), onClose: { selection = [] }) {
                    if let row, let serverURL = store.serverURL {
                        MacOfflineInspector(
                            row: row,
                            serverURL: serverURL,
                            onOpen: { open(row) },
                            onRemove: { remove(row) },
                            onClose: { selection = [] }
                        )
                    }
                }
        }

        private func isOpen(_ row: MacOfflineTableRow?) -> Bool {
            row != nil && store.serverURL != nil && store.path.isEmpty && store.previewHost == nil
        }

        private func open(_ row: MacOfflineTableRow) {
            switch row {
            case let .pinned(usage): store.send(.pinnedItemTapped(usage.root))
            case let .saved(download): onPreview(download)
            }
        }

        private func remove(_ row: MacOfflineTableRow) {
            switch row {
            case let .pinned(usage):
                offlineStore.send(.removeSelectionTapped(paths: [usage.root.path]), animation: DSMotion.listDiff)
            case let .saved(download):
                store.send(.deleteTapped(download))
            }
        }
    }

    private enum PreviewFixture {
        static let serverURL = URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")
        static let folder = MacOfflineTableRow.pinned(OfflinePinnedRootUsage(
            root: OfflinePinnedRoot(path: "Team Library", isDirectory: true),
            sizeBytes: 16_800_000
        ))
        static let file = MacOfflineTableRow.pinned(OfflinePinnedRootUsage(
            root: OfflinePinnedRoot(path: "Documents/Welcome.pdf", isDirectory: false),
            sizeBytes: 184_000
        ))
        static let saved = MacOfflineTableRow.saved(LocalDownload(
            url: URL(fileURLWithPath: "/nonexistent/report.pdf"),
            fileName: "report.pdf",
            size: 2_400_000,
            modifiedDate: .distantPast
        ))

        @MainActor
        static func inspector(_ row: MacOfflineTableRow) -> some View {
            MacOfflineInspector(row: row, serverURL: serverURL, onOpen: {}, onRemove: {}, onClose: {})
                .frame(width: MacInspectorMetrics.width, height: MacPeekMetrics.previewHeight)
                .background(Color.macCard)
        }
    }

    #Preview("Pinned folder") {
        PreviewFixture.inspector(PreviewFixture.folder)
    }

    #Preview("Pinned file") {
        PreviewFixture.inspector(PreviewFixture.file)
    }

    #Preview("Saved earlier") {
        PreviewFixture.inspector(PreviewFixture.saved)
    }
#endif

extension View {
    func macOfflineInspector(
        _ store: StoreOf<OfflineTabFeature>,
        _ offlineStore: StoreOf<OfflineManageFeature>,
        pinned: [OfflinePinnedRootUsage],
        onPreview: @escaping (LocalDownload) -> Void
    ) -> some View {
        #if os(macOS)
            modifier(MacOfflineInspectorPane(
                store: store,
                offlineStore: offlineStore,
                pinned: pinned,
                onPreview: onPreview
            ))
        #elseif os(iOS)
            self
        #endif
    }
}
