#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Constants {
        static let listedVersions = 5
    }

    struct MacVersionsMenu<MenuLabel: View>: View {
        let store: StoreOf<BrowseFeature>
        let item: FileItem
        @ViewBuilder let label: () -> MenuLabel
        var onPick: () -> Void = {}
        @Environment(VersionsModel.self) private var versions: VersionsModel?

        var body: some View {
            if let versions {
                let phase = versions.menuPhase(for: item)
                if phase != .hidden {
                    Menu {
                        entries(phase, versions: versions)
                    } label: {
                        label()
                    }
                }
            }
        }

        @ViewBuilder
        private func entries(_ phase: VersionsMenuPhase, versions: VersionsModel) -> some View {
            switch phase {
            case .hidden, .unloaded:
                EmptyView()
            case .loading:
                Button(L10n.Common.loading) {}
                    .disabled(true)
            case let .loaded(history):
                if history.versions.isEmpty {
                    Button(L10n.FileInfo.versionsNone) {}
                        .disabled(true)
                }
                ForEach(history.versions.prefix(Constants.listedVersions)) { version in
                    let title = version.label ?? VersionsModel.date(version.modifiedAt)
                    if version.isAvailable != false, history.rights.canActOnVersion {
                        Menu(title) {
                            if history.rights.canRestore {
                                Button(L10n.FileInfo.versionRestore) {
                                    onPick(); versions.beginRestore(version, of: item)
                                }
                            }
                            if history.rights.canDownload {
                                Button(L10n.FileInfo.versionDownload) { onPick(); versions.download(version, of: item) }
                                if store.canCreateFileHere {
                                    Button(L10n.FileInfo.versionSaveCopy) { onPick(); versions.saveCopy(
                                        version,
                                        of: item
                                    ) }
                                }
                            }
                        }
                    } else {
                        Button(title) {}
                            .disabled(true)
                    }
                }
            }
            if phase != .unloaded {
                Divider()
            }
            Button(L10n.Browse.actionShowAllVersions) {
                onPick()
                versions.revealRequest = item.id
                store.send(.infoTapped(item))
            }
        }
    }

    private extension FileVersionHistory.Rights {
        var canActOnVersion: Bool {
            canRestore || canDownload
        }
    }

    extension MacVersionsMenu where MenuLabel == Label<Text, Image> {
        init(store: StoreOf<BrowseFeature>, item: FileItem) {
            self.init(store: store, item: item) {
                Label { Text(L10n.Browse.actionVersions) } icon: { MenuIcon.versions.image }
            }
        }
    }

    #Preview("Versions menu") {
        let item = browsePreviewItems[2]
        let model = withDependencies {
            $0.filesClient.serverFeatures = { _ in ServerFeatures(isVersionsEnabled: true) }
        } operation: {
            VersionsModel()
        }
        MacVersionsMenu(store: Store(initialState: .preview(items: browsePreviewItems)) { BrowseFeature() }, item: item)
            .environment(model)
            .task { await model.load(item: item, serverURL: URL(fileURLWithPath: "/"), account: "") }
            .padding()
    }
#endif
