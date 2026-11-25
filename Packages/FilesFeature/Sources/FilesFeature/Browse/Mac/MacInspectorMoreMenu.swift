#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
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

        private var access: FileAccess? {
            store.access
        }

        private var canWrite: Bool {
            access?.canWrite ?? false
        }

        private var canDelete: Bool {
            access?.canDelete ?? false
        }

        private var isOffline: Bool {
            store.offlineItemIDs.contains(item.id)
        }

        private var hasOrganizeActions: Bool {
            canWrite || !store.shouldShowDeviceContent
        }

        var body: some View {
            if store.items[id: item.id] == nil {
                currentFolderActions
            } else {
                listedItemActions
            }
        }

        @ViewBuilder
        private var currentFolderActions: some View {
            if access?.canDownload ?? false {
                MacActionMenuButton(SaveActionStyle.title, icon: IconKit.menuDownload) {
                    store.send(.downloadTapped(item))
                }
            }
            if !store.shouldShowDeviceContent {
                MacActionMenuButton(L10n.Browse.actionCopyTo, icon: IconKit.share) {
                    store.send(.copyToTapped(item))
                }
            }
        }

        @ViewBuilder
        private var listedItemActions: some View {
            if !item.isDirectory {
                MacInspectorOpenWithRow(item: item, serverURL: store.serverURL, onFailure: onOpenWithFailed)
            }
            if store.shouldShowDeviceContent, isOffline, !item.isDirectory {
                MacLocalFilePanelRows(resolve: keptCopy)
            } else if access?.canDownload ?? false, !store.shouldShowDeviceContent {
                MacActionMenuButton(SaveActionStyle.title, icon: IconKit.menuDownload) {
                    store.send(.downloadTapped(item))
                }
            }
            if access?.canDownload ?? false, !isOffline, !store.shouldShowDeviceContent {
                MacActionMenuButton(L10n.Browse.actionKeepOffline, icon: IconKit.menuKeepOffline) {
                    store.send(.offlineToggleTapped(item))
                }
            }
            MacActionMenuButton(L10n.Browse.actionShowInFolder, icon: IconKit.folder) {
                store.send(.showInFolderTapped(item))
            }
            if hasOrganizeActions {
                MacActionMenuDivider()
                organizeActions
            }
            if isOffline || canDelete {
                MacActionMenuDivider()
            }
            if isOffline {
                MacActionMenuButton(
                    L10n.Browse.actionRemoveFromOffline,
                    icon: IconKit.menuKeepOffline,
                    isDestructive: true
                ) {
                    store.send(.offlineToggleTapped(item))
                }
            }
            if canDelete {
                MacDeleteMenuButton(isTrashAvailable: store.isTrashAvailable) {
                    store.send(.deleteTapped(item))
                }
            }
        }

        private var keptCopy: @Sendable () -> URL? {
            @Dependency(\.offlineFileStore) var offlineFileStore
            let store = offlineFileStore.pinned(to: store.cacheScope)
            let item = item
            return { store.localURLIgnoringStaleness(item) }
        }

        @ViewBuilder
        private var organizeActions: some View {
            if canWrite {
                MacActionMenuButton(
                    L10n.ellipsized(L10n.Browse.actionRename),
                    icon: IconKit.pencil,
                    accessory: .shortcut(MacMenuShortcut.rename)
                ) {
                    store.send(.renameTapped(item))
                }
                if !store.directoryPath.isEmpty {
                    MacActionMenuButton(
                        L10n.Browse.actionDuplicate,
                        icon: IconKit.menuDuplicate,
                        accessory: .shortcut(MacMenuShortcut.duplicate)
                    ) {
                        store.send(.tableSelectionChanged([item.id]))
                        store.send(.duplicateSelectionTapped, animation: DSMotion.listDiff)
                    }
                }
            }
            if canWrite, canDelete {
                MacActionMenuButton(L10n.Browse.actionMoveTo, icon: IconKit.menuMoveTo) {
                    store.send(.moveTapped(item))
                }
            }
            if !store.shouldShowDeviceContent {
                MacActionMenuButton(L10n.Browse.actionCopyTo, icon: IconKit.share) {
                    store.send(.copyToTapped(item))
                }
            }
            if canWrite {
                MacActionMenuButton(L10n.Browse.actionCompress, icon: IconKit.extract) {
                    store.send(.compressTapped(item))
                }
            }
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
