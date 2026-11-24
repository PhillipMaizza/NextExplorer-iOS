#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    struct MacPeekOverlay<More: View>: ViewModifier {
        let store: StoreOf<BrowseFeature>
        @Binding var isPeeking: Bool
        let onOpen: (FileItem) -> Void
        let onShare: (FileItem) -> Void
        @ViewBuilder let more: (FileItem) -> More

        @Environment(MacPeekHost.self) private var host: MacPeekHost?

        private var owner: ObjectIdentifier {
            ObjectIdentifier(store)
        }

        private var item: FileItem? {
            guard store.selectedItemIDs.count == 1, let id = store.selectedItemIDs.first else { return nil }
            return store.displayedItems.first { $0.id == id }
        }

        func body(content: Content) -> some View {
            content
                .onChange(of: isPeeking ? item?.id : nil, initial: true) { present() }
                .onChange(of: store.directoryPath) { isPeeking = false }
                .onDisappear {
                    isPeeking = false
                    host?.hide(owner: owner)
                }
        }

        private func present() {
            guard isPeeking, let item else {
                isPeeking = false
                host?.hide(owner: owner)
                return
            }
            host?.show(
                MacPeekStoreCard(
                    store: store,
                    item: item,
                    onOpen: {
                        isPeeking = false
                        onOpen(item)
                    },
                    onShare: { onShare(item) },
                    onClose: { isPeeking = false },
                    more: { more(item) }
                ),
                owner: owner
            ) { isPeeking = false }
        }
    }

    struct MacPeekStoreCard<More: View>: View {
        let store: StoreOf<BrowseFeature>
        let item: FileItem
        let onOpen: () -> Void
        let onShare: () -> Void
        let onClose: () -> Void
        @ViewBuilder let more: () -> More

        var body: some View {
            MacPeekCard(
                item: item,
                subtitle: subtitle,
                position: position,
                serverURL: store.serverURL,
                isSavedOffline: store.offlineItemIDs.contains(item.id),
                shouldShowThumbnails: store.preferences.shouldShowThumbnails,
                showsHiddenFiles: store.preferences.shouldShowHiddenFiles,
                onOpen: onOpen,
                onShare: (store.access?.canShare ?? false) ? onShare : nil,
                onStep: step,
                onClose: onClose,
                more: more
            )
        }

        private func step(by offset: Int) {
            let items = store.displayedItems
            guard let index = items.firstIndex(where: { $0.id == item.id }),
                  items.indices.contains(index + offset) else { return }
            store.send(.tableSelectionChanged([items[index + offset].id]))
        }

        private var subtitle: String {
            let kind = item.isDirectory ? L10n.FileInfo.navigationTitleFolder : item.previewTypeText
            let size = item.isDirectory ? store.folderSizes[item.id] : item.size
            return ([kind] + [size.map(FileSizeFormat.string)].compactMap(\.self))
                .joined(separator: MacPeekMetrics.separator)
        }

        private var position: String {
            let items = store.displayedItems
            let index = items.firstIndex { $0.id == item.id } ?? .zero
            return L10n.PdfPreview.pageIndicator(index + 1, items.count)
        }
    }

    #Preview("Store card") {
        let item = browsePreviewItems.first { !$0.isDirectory } ?? browsePreviewItems[0]
        MacPeekStoreCard(
            store: Store(initialState: .preview(items: browsePreviewItems)) { BrowseFeature() },
            item: item,
            onOpen: {},
            onShare: {},
            onClose: {},
            more: { EmptyView() }
        )
        .padding(MacPeekMetrics.margin)
        .background(Color.macChrome)
    }
#endif
