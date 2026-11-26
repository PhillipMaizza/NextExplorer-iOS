#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    enum MacMenuShortcut {
        static let rename = "\u{21B5}"
        static let duplicate = "\u{2318}D"
        static let delete = "\u{2318}\u{232B}"
    }

    struct MacInspectorMoreMenu: View {
        let store: StoreOf<BrowseFeature>
        let item: FileItem
        let onOpenWithFailed: (String) -> Void

        @Dependency(\.offlineFileStore) private var offlineFileStore

        private var rows: InspectorMoreRows {
            store.state.inspectorMoreRows(for: item)
        }

        var body: some View {
            let rows = rows
            if rows.isListed {
                listedItemActions(rows)
            } else {
                downloadAction(rows)
                if rows.actions.canCopy {
                    MacActionMenuButton(L10n.Browse.actionCopyTo, icon: IconKit.share) {
                        store.send(.copyToTapped(item))
                    }
                }
            }
        }

        @ViewBuilder
        private func downloadAction(_ rows: InspectorMoreRows) -> some View {
            if rows.showsDownload {
                MacActionMenuButton(SaveActionStyle.title, icon: IconKit.menuDownload) {
                    store.send(.downloadTapped(item))
                }
            }
        }

        @ViewBuilder
        private func listedItemActions(_ rows: InspectorMoreRows) -> some View {
            if rows.showsOpenWith {
                MacInspectorOpenWithRow(item: item, serverURL: store.serverURL, onFailure: onOpenWithFailed)
            }
            if rows.showsKeptCopy {
                MacLocalFilePanelRows(resolve: offlineFileStore.pinned(to: store.cacheScope).keptCopy(of: item))
            }
            downloadAction(rows)
            if rows.showsKeepOffline {
                MacActionMenuButton(L10n.Browse.actionKeepOffline, icon: IconKit.menuKeepOffline) {
                    store.send(.offlineToggleTapped(item))
                }
            }
            if rows.actions.hasOrganizeActions {
                MacActionMenuDivider()
                organizeActions(rows.actions)
            }
            if rows.showsRemoveFromOffline || rows.actions.canDelete {
                MacActionMenuDivider()
            }
            if rows.showsRemoveFromOffline {
                MacActionMenuButton(
                    L10n.Browse.actionRemoveFromOffline,
                    icon: IconKit.menuKeepOffline,
                    isDestructive: true
                ) {
                    store.send(.offlineToggleTapped(item))
                }
            }
            if rows.actions.canDelete {
                MacDeleteMenuButton(isTrashAvailable: store.isTrashAvailable) {
                    store.send(.deleteTapped(item))
                }
            }
        }

        @ViewBuilder
        private func organizeActions(_ actions: FileItemActions) -> some View {
            if actions.canRename {
                MacActionMenuButton(
                    L10n.ellipsized(L10n.Browse.actionRename),
                    icon: IconKit.pencil,
                    accessory: .shortcut(MacMenuShortcut.rename)
                ) {
                    store.send(.renameTapped(item))
                }
            }
            if actions.canDuplicate {
                MacActionMenuButton(
                    L10n.Browse.actionDuplicate,
                    icon: IconKit.menuDuplicate,
                    accessory: .shortcut(MacMenuShortcut.duplicate)
                ) {
                    store.send(.tableSelectionChanged([item.id]))
                    store.send(.duplicateSelectionTapped, animation: DSMotion.listDiff)
                }
            }
            if actions.canMove {
                MacActionMenuButton(L10n.Browse.actionMoveTo, icon: IconKit.menuMoveTo) {
                    store.send(.moveTapped(item))
                }
            }
            if actions.canCopy {
                MacActionMenuButton(L10n.Browse.actionCopyTo, icon: IconKit.share) {
                    store.send(.copyToTapped(item))
                }
            }
            if actions.canExtract {
                MacActionMenuButton(L10n.Browse.actionExtract, icon: IconKit.extract) {
                    store.send(.extractTapped(item))
                }
            }
            if actions.canCompress {
                MacActionMenuButton(L10n.Browse.actionCompress, icon: IconKit.archiveDocument) {
                    store.send(.compressTapped(item))
                }
            }
        }
    }

    struct InspectorMoreRows: Equatable {
        var actions = FileItemActions()
        var isListed = false
        var showsOpenWith = false
        var showsKeptCopy = false
        var showsDownload = false
        var showsKeepOffline = false
        var showsRemoveFromOffline = false

        var isEmpty: Bool {
            let listedRows = showsOpenWith || showsKeptCopy || showsKeepOffline || showsRemoveFromOffline
                || actions.hasOrganizeActions || actions.canDelete
            return !showsDownload && !(isListed ? listedRows : actions.canCopy)
        }
    }

    extension BrowseFeature.State {
        func inspectorMoreRows(for item: FileItem) -> InspectorMoreRows {
            let actions = actions(for: item)
            let isListed = items[id: item.id] != nil
            let isOffline = offlineItemIDs.contains(item.id)
            let showsKeptCopy = isListed && shouldShowDeviceContent && isOffline && !item.isDirectory
            return InspectorMoreRows(
                actions: actions,
                isListed: isListed,
                showsOpenWith: isListed && !item.isDirectory && actions.canExport,
                showsKeptCopy: showsKeptCopy,
                showsDownload: !showsKeptCopy && actions.canDownload && !shouldShowDeviceContent,
                showsKeepOffline: isListed && actions.canKeepOffline && !isOffline,
                showsRemoveFromOffline: isListed && isOffline
            )
        }
    }

    private struct MacInspectorOpenWithRow: View {
        let item: FileItem
        let serverURL: URL
        let onFailure: (String) -> Void

        var body: some View {
            let apps = MacOpenWithApp.apps(forFileNamed: item.name).all
            Menu {
                ForEach(apps) { app in
                    Button { open(with: app) } label: {
                        Label { Text(app.name) } icon: { app.icon }
                    }
                }
            } label: {
                MacActionMenuRow(L10n.OpenWith.openWith, icon: IconKit.menuOpenWith, accessory: .submenu)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .disabled(apps.isEmpty)
        }

        private func open(with app: MacOpenWithApp) {
            MacOpenWithModel(source: .remote(item, serverURL: serverURL), onFailure: onFailure).open(with: app)
        }
    }

    struct MacDeleteMenuButton: View {
        let isTrashAvailable: Bool
        let action: () -> Void

        var body: some View {
            MacActionMenuButton(
                isTrashAvailable ? L10n.Trash.moveToTrash : L10n.Browse.actionDelete,
                icon: IconKit.delete,
                accessory: .shortcut(MacMenuShortcut.delete),
                isDestructive: true,
                action: action
            )
        }
    }

    #Preview("Delete item") {
        MacActionMenuPanel {
            MacDeleteMenuButton(isTrashAvailable: true) {}
            MacDeleteMenuButton(isTrashAvailable: false) {}
        }
    }

    #Preview("More menu") {
        let item = FileItem(name: "portrait.dng", path: "Photos", dateModified: .distantPast, size: 1, kind: "dng")
        var state = BrowseFeature.State(serverURL: URL(fileURLWithPath: "/"), directoryPath: "Photos", title: "Photos")
        state.items = [item]
        state.access = FileAccess(
            canRead: true,
            canWrite: true,
            canUpload: true,
            canDelete: true,
            canShare: true,
            canDownload: true
        )
        state.isTrashAvailable = true
        return MacActionMenuPanel {
            MacInspectorMoreMenu(store: Store(initialState: state) { BrowseFeature() }, item: item) { _ in }
        }
        .background(Color.macCard)
    }
#endif
