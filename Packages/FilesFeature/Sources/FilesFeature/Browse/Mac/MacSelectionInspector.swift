#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let stackSize: CGFloat = 72
        static let stackTile: CGFloat = 54
        static let stackStep: CGFloat = 9
        static let stackRing: CGFloat = 3
        static let stackCornerFraction: CGFloat = 0.28
        static let stackLimit = 3
        static let rowTile: CGFloat = .size24
        static let rowLimit = 50
    }

    struct MacSelectionInspector: View {
        let store: StoreOf<BrowseFeature>
        let onClose: () -> Void

        @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue

        var body: some View {
            let items = store.selectedItems
            let availability = store.selectionAvailability
            ScrollView {
                VStack(alignment: .leading, spacing: MacInspectorMetrics.sectionSpacing) {
                    header(items)
                    MacInspectorQuickActions(
                        actions: quickActions(availability),
                        showsMore: MacSelectionMoreMenu.hasActions(availability, directoryPath: store.directoryPath)
                    ) {
                        MacSelectionMoreMenu(store: store)
                    }
                    MacInspectorGroup {
                        if let total = totalSize(items) {
                            MacInspectorRow(L10n.FileInfo.rowTotalSize, total)
                        }
                        if let location = location(items) {
                            MacInspectorRow(L10n.FileInfo.rowWhere, location, icon: IconKit.folderFill)
                        }
                        MacInspectorRow(L10n.FileInfo.rowModified, modifiedRange(items), valueLineLimit: 2)
                    }
                    selectedList(items)
                    Text(L10n.FileInfo.selectionFootnote)
                        .type(.caption(.regular), style: .secondary)
                }
                .padding(MacInspectorMetrics.padding)
            }
            .scrollIndicators(.never)
            .defaultScrollAnchor(.top)
        }

        private func header(_ items: [FileItem]) -> some View {
            HStack(alignment: .top, spacing: .space16) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(items.prefix(Metrics.stackLimit).enumerated()), id: \.element.id) { index, item in
                        MacItemTile(kind: item.kind, isDirectory: item.isDirectory, size: Metrics.stackTile)
                            .background(
                                RoundedRectangle(
                                    cornerRadius: Metrics.stackTile * Metrics.stackCornerFraction + Metrics.stackRing,
                                    style: .continuous
                                )
                                .fill(Color.macCard)
                                .padding(-Metrics.stackRing)
                            )
                            .offset(x: CGFloat(index) * Metrics.stackStep, y: CGFloat(index) * Metrics.stackStep)
                    }
                }
                .frame(width: Metrics.stackSize, height: Metrics.stackSize, alignment: .topLeading)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: .space4) {
                    Text(L10n.Shared.itemCount(items.count))
                        .type(.headline4)
                    Text(kinds(items))
                        .type(.body3(.regular), style: .secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, .space4)
                MacInspectorCloseButton(action: onClose)
            }
        }

        private func quickActions(_ availability: SelectionActionsMenu.Availability) -> [MacInspectorQuickAction] {
            var actions: [MacInspectorQuickAction] = []
            if availability.canSave {
                actions.append(MacInspectorQuickAction(
                    id: .download,
                    icon: IconKit.menuDownload,
                    title: SaveActionStyle.title
                ) { store.send(.bulkDownloadTapped) })
            }
            if availability.canFavorite {
                actions.append(MacInspectorQuickAction(
                    id: .favorite,
                    icon: availability.isAllFavorite ? IconKit.starFill : IconKit.star,
                    title: L10n.FileInfo.quickFavorite,
                    isOn: availability.isAllFavorite,
                    isEnabled: availability.hasLoadedFavorites
                ) { store.send(.bulkFavoriteTapped) })
            }
            return actions
        }

        private func selectedList(_ items: [FileItem]) -> some View {
            VStack(alignment: .leading, spacing: .space8) {
                MacInspectorSectionHeader(title: L10n.FileInfo.sectionSelected)
                MacInspectorGroup {
                    ForEach(items.prefix(Metrics.rowLimit)) { item in
                        HStack(spacing: .space8) {
                            MacItemTile(kind: item.kind, isDirectory: item.isDirectory, size: Metrics.rowTile)
                            Text(item.name)
                                .type(.body3(.regular))
                                .foregroundStyle(Color.primaryDS)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: .space8)
                            Text(FileSizeFormat.string(for: item, folderSize: store.folderSizes[item.id]))
                                .type(.body3(.regular), style: .secondary)
                                .monospacedDigit()
                                .fixedSize()
                        }
                        .frame(minHeight: MacInspectorMetrics.rowHeight)
                        .accessibilityElement(children: .combine)
                    }
                    if items.count > Metrics.rowLimit {
                        Text(L10n.FileInfo.moreSelected(items.count - Metrics.rowLimit))
                            .type(.body3(.regular), style: .secondary)
                            .frame(maxWidth: .infinity, minHeight: MacInspectorMetrics.rowHeight, alignment: .leading)
                    }
                }
            }
        }

        private func kinds(_ items: [FileItem]) -> String {
            var titles: [String] = []
            for item in items {
                let title = item.isDirectory ? L10n.FileInfo.navigationTitleFolder : item.kind.uppercased()
                if !title.isEmpty, !titles.contains(title) {
                    titles.append(title)
                }
            }
            return titles.formatted(.list(type: .and, width: .narrow))
        }

        private func totalSize(_ items: [FileItem]) -> String? {
            var total: Int64 = 0
            for item in items {
                if item.isDirectory {
                    guard let size = store.folderSizes[item.id] else { return nil }
                    total += size
                } else {
                    total += item.size
                }
            }
            return FileSizeFormat.string(total)
        }

        private func location(_ items: [FileItem]) -> String? {
            let parents = Set(items.map(MacInspectorLocation.parent(of:)))
            guard parents.count == 1, let parent = parents.first else { return nil }
            return MacInspectorLocation.title(parent: parent)
        }

        private func modifiedRange(_ items: [FileItem]) -> String {
            let format = DateDisplayFormat(rawValue: dateFormatRaw) ?? .system
            let dates = items.filter(\.hasKnownDate).map(\.dateModified)
            guard let first = dates.min(), let last = dates.max() else { return L10n.Browse.noValue }
            let start = format.string(from: first, includeTime: false)
            let end = format.string(from: last, includeTime: false)
            guard start != end else { return start }
            guard format == .system else { return L10n.FileInfo.dateRange(start, end) }
            return (first ..< last).formatted(.interval.day().month(.abbreviated).year())
        }
    }

    private struct MacSelectionMoreMenu: View {
        let store: StoreOf<BrowseFeature>

        static func hasActions(_ availability: SelectionActionsMenu.Availability, directoryPath: String) -> Bool {
            hasOfflineAction(availability) || hasOrganizeActions(availability, directoryPath: directoryPath)
                || availability.canDelete
        }

        private static func hasOfflineAction(_ availability: SelectionActionsMenu.Availability) -> Bool {
            availability.canKeepOffline && availability.offlineAction != nil
        }

        private static func hasOrganizeActions(
            _ availability: SelectionActionsMenu.Availability,
            directoryPath: String
        ) -> Bool {
            (availability.canWrite && !directoryPath.isEmpty) || availability.canMove || availability.canTransfer
        }

        var body: some View {
            let availability = store.selectionAvailability
            let hasOrganize = Self.hasOrganizeActions(availability, directoryPath: store.directoryPath)
            if Self.hasOfflineAction(availability), let action = availability.offlineAction {
                MacActionMenuButton(
                    action == .remove ? L10n.Browse.actionRemoveFromOffline : L10n.Browse.actionKeepOffline,
                    icon: IconKit.menuKeepOffline,
                    isDestructive: action == .remove
                ) {
                    store.send(.bulkOfflineTapped)
                }
                if hasOrganize || availability.canDelete {
                    MacActionMenuDivider()
                }
            }
            if availability.canWrite, !store.directoryPath.isEmpty {
                MacActionMenuButton(
                    L10n.Browse.actionDuplicate,
                    icon: IconKit.menuDuplicate,
                    accessory: .shortcut(MacMenuShortcut.duplicate)
                ) {
                    store.send(.duplicateSelectionTapped, animation: DSMotion.listDiff)
                }
            }
            if availability.canMove {
                MacActionMenuButton(L10n.Browse.actionMoveTo, icon: IconKit.menuMoveTo) {
                    store.send(.bulkMoveTapped)
                }
            }
            if availability.canTransfer {
                MacActionMenuButton(L10n.Browse.actionCopyTo, icon: IconKit.share) {
                    store.send(.copySelectionToTapped)
                }
            }
            if availability.canDelete {
                if hasOrganize {
                    MacActionMenuDivider()
                }
                MacDeleteMenuButton(isTrashAvailable: store.isTrashAvailable) {
                    store.send(.deleteSelectionTapped)
                }
            }
        }
    }

    @MainActor
    private enum PreviewFixture {
        static let access = FileAccess(
            canRead: true,
            canWrite: true,
            canUpload: true,
            canDelete: true,
            canShare: true,
            canDownload: true
        )

        static func file(_ name: String, kind: String, size: Int64, daysAgo: Double) -> FileItem {
            FileItem(
                name: name,
                path: "Documents",
                dateModified: Date(timeIntervalSinceReferenceDate: 815_000_000 - daysAgo * 86_400),
                size: size,
                kind: kind
            )
        }

        static func store(
            _ items: [FileItem],
            folderSizes: [FileItem.ID: Int64] = [:],
            access: FileAccess = access
        ) -> StoreOf<BrowseFeature> {
            var state = BrowseFeature.State(
                serverURL: URL(fileURLWithPath: "/"),
                directoryPath: "Documents",
                title: "Documents"
            )
            state.items = IdentifiedArray(uniqueElements: items)
            state.selectedItemIDs = Set(items.map(\.id))
            state.access = access
            state.folderSizes = folderSizes
            state.isInfoShowingSelection = true
            state.isTrashAvailable = true
            return Store(initialState: state) { BrowseFeature() }
        }

        static func inspector(
            _ items: [FileItem],
            folderSizes: [FileItem.ID: Int64] = [:],
            access: FileAccess = access
        ) -> some View {
            MacSelectionInspector(store: store(items, folderSizes: folderSizes, access: access)) {}
                .frame(width: MacInspectorMetrics.width, height: 880)
                .background(Color.macCard)
        }
    }

    #Preview("Files") {
        PreviewFixture.inspector([
            PreviewFixture.file("Contract signed.pdf", kind: "pdf", size: 655_000, daysAgo: 236),
            PreviewFixture.file("Budget 2026.xlsx", kind: "xlsx", size: 90_000, daysAgo: 12),
            PreviewFixture.file("Proposal.docx", kind: "docx", size: 225_000, daysAgo: 0),
        ])
    }

    #Preview("Folders and files") {
        let invoices = FileItem(
            name: "Invoices",
            path: "Documents",
            dateModified: .distantPast,
            size: 0,
            kind: "directory"
        )
        let photos = FileItem(name: "Photos", path: "Documents", dateModified: .distantPast, size: 0, kind: "directory")
        return PreviewFixture.inspector(
            [invoices, photos, PreviewFixture.file("notes.txt", kind: "txt", size: 4_000, daysAgo: 3)],
            folderSizes: [invoices.id: 12_400_000]
        )
    }

    #Preview("Folders only") {
        let invoices = FileItem(
            name: "Invoices",
            path: "Documents",
            dateModified: .distantPast,
            size: 0,
            kind: "directory"
        )
        let photos = FileItem(name: "Photos", path: "Documents", dateModified: .distantPast, size: 0, kind: "directory")
        return PreviewFixture.inspector([invoices, photos], folderSizes: [invoices.id: 12_400_000, photos.id: 800_000])
    }

    #Preview("More menu") {
        MacActionMenuPanel {
            MacSelectionMoreMenu(store: PreviewFixture.store([
                PreviewFixture.file("notes.txt", kind: "txt", size: 4_000, daysAgo: 3),
                PreviewFixture.file("draft.txt", kind: "txt", size: 2_000, daysAgo: 1),
            ]))
        }
        .background(Color.macCard)
    }

    #Preview("Read only") {
        PreviewFixture.inspector(
            [
                PreviewFixture.file("notes.txt", kind: "txt", size: 4_000, daysAgo: 3),
                PreviewFixture.file("draft.txt", kind: "txt", size: 2_000, daysAgo: 1),
            ],
            access: FileAccess(
                canRead: true,
                canWrite: false,
                canUpload: false,
                canDelete: false,
                canShare: false,
                canDownload: false
            )
        )
    }

    #Preview("Many items") {
        PreviewFixture.inspector((1 ... 64).map {
            PreviewFixture.file("IMG_\($0).jpg", kind: "jpg", size: 2_400_000, daysAgo: Double($0))
        })
    }
#endif
