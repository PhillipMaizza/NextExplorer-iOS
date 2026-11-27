#if os(iOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import FolderPickerFeature
    import Localization
    import SwiftUI

    private enum Constants {
        static let backIconSize: CGFloat = .iconSmall
        static let assetsFolder = "assets"
    }

    private struct ArchiveEntryPreview: Identifiable, Equatable {
        let item: FileItem
        let fileURL: URL

        var id: String {
            fileURL.path
        }
    }

    struct ArchiveBrowserView: View {
        let item: FileItem
        let serverURL: URL
        let onDismiss: () -> Void

        @State private var store: StoreOf<ArchiveBrowserFeature>
        @State private var toastMessage: DSToastMessage?
        @Dependency(\.filesClient) private var filesClient
        @Dependency(\.archiveReader) private var archiveReader

        init(item: FileItem, serverURL: URL, localFileURL: URL? = nil, onDismiss: @escaping () -> Void) {
            self.item = item
            self.serverURL = serverURL
            self.onDismiss = onDismiss
            _store = State(initialValue: Store(
                initialState: ArchiveBrowserFeature.State(
                    archive: item,
                    serverURL: serverURL,
                    localFileURL: localFileURL
                )
            ) { ArchiveBrowserFeature() })
        }

        private var openedPreview: Binding<ArchiveEntryPreview?> {
            Binding(
                get: {
                    guard let entry = store.entry, case let .loaded(url) = entry.phase,
                          let file = store.files.first(where: { $0.path == entry.path }) else { return nil }
                    return ArchiveEntryPreview(item: file.fileItem, fileURL: url)
                },
                set: { preview in
                    if preview == nil, store.entry != nil {
                        store.send(.backTapped)
                    }
                }
            )
        }

        private var thumbnails: ArchiveThumbnailLoader? {
            ArchiveThumbnailLoader(archive: item, serverURL: serverURL, source: store.source)
        }

        var body: some View {
            NavigationStack {
                content
                    .backgroundGradient()
                    .navigationTitle(store.path.last ?? item.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbar }
            }
            .dsToast($toastMessage)
            .fullScreenCover(item: openedPreview) { preview in
                ArchiveEntryPreviewView(
                    item: preview.item,
                    fileURL: preview.fileURL,
                    serverURL: serverURL,
                    resolveAsset: { relativePath in
                        await resolveAsset(relativePath, relativeTo: preview.item.path)
                    },
                    onDismiss: { store.send(.backTapped) }
                )
            }
            .onChange(of: entryFailure) { _, failure in
                guard let failure else { return }
                toastMessage = DSToastMessage(icon: IconKit.errorFill, text: failure)
                store.send(.backTapped)
            }
            .task { store.send(.task) }
            .onDisappear {
                store.send(.closed)
                let directory = ArchiveBrowserFeature.scratchDirectory(for: item)
                Task.detached(priority: .utility) {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }

        private var entryFailure: String? {
            guard case let .failed(message)? = store.entry?.phase else { return nil }
            return message
        }

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            if !store.path.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button { store.send(.backTapped) } label: {
                        IconKit.back
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(Color.primaryDS)
                            .frame(width: Constants.backIconSize, height: Constants.backIconSize)
                    }
                    .accessibilityLabel(L10n.Common.back)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { onDismiss() } label: {
                    IconKit.close.foregroundStyle(Color.primaryDS)
                }
                .accessibilityLabel(L10n.Common.close)
            }
        }

        @ViewBuilder
        private var content: some View {
            if let failure = store.phase.errorMessage {
                EmptyStateView(icon: IconKit.warning, message: failure) { store.send(.retryTapped) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.phase != .loaded {
                DSSpinner()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.entries.isEmpty {
                EmptyStateView(icon: IconKit.folderFill, message: L10n.Archive.emptyFolder)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    FileGrid {
                        ForEach(store.entries) { entry in
                            Button {
                                store.send(.fileOpened(entry))
                            } label: {
                                ArchiveTile(
                                    entry: entry,
                                    thumbnails: thumbnails,
                                    isOpening: store.entry?.path == entry.path && store.entry?.phase == .loading
                                )
                            }
                            .buttonStyle(DSPressableButtonStyle())
                            .disabled(store.entry?.phase == .loading)
                        }
                    }
                    .padding(FileGridMetrics.margin)
                }
            }
        }

        private func resolveAsset(_ relativePath: String, relativeTo directory: String) async -> URL? {
            guard let resolved = RelativeAssetPath.resolve(relativePath, relativeTo: directory) else { return nil }
            let entryPath = resolved.parent.isEmpty ? resolved.name : "\(resolved.parent)/\(resolved.name)"
            let base = ArchiveBrowserFeature.scratchDirectory(for: item)
                .appendingPathComponent(Constants.assetsFolder, isDirectory: true)
            guard let destination = SafeDestination.within(base, entryPath) else { return nil }
            try? FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: destination)
            switch store.source {
            case .unresolved:
                return nil
            case .server:
                guard let downloaded = try? await filesClient.downloadArchiveEntry(serverURL, item, entryPath),
                      (try? FileManager.default.moveItem(at: downloaded, to: destination)) != nil else { return nil }
                return destination
            case let .local(url):
                return await (try? archiveReader.extract(url, item.kind, entryPath, destination)) != nil
                    ? destination
                    : nil
            }
        }
    }

    #Preview("Loading") {
        ArchiveBrowserView(
            item: FileItem(name: "bundle.zip", path: "", dateModified: Date(), size: 0, kind: "zip"),
            serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
            onDismiss: {}
        )
    }
#endif
