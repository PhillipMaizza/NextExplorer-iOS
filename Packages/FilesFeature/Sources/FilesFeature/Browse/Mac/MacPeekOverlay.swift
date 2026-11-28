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

        private var item: FileItem? {
            guard store.selectedItemIDs.count == 1, let id = store.selectedItemIDs.first else { return nil }
            return store.displayedItems.first { $0.id == id }
        }

        func body(content: Content) -> some View {
            content
                .modifier(MacItemPeek(
                    item: item,
                    items: store.displayedItems.elements,
                    isPeeking: $isPeeking,
                    serverURL: store.serverURL,
                    shouldShowThumbnails: store.preferences.shouldShowThumbnails,
                    showsHiddenFiles: store.preferences.shouldShowHiddenFiles,
                    isSavedOffline: { store.offlineItemIDs.contains($0.id) },
                    size: { $0.isDirectory ? store.folderSizes[$0.id] : $0.size },
                    onSelect: { store.send(.tableSelectionChanged([$0.id])) },
                    onOpen: onOpen,
                    onShare: item.map { store.state.actions(for: $0).canShare } ?? false ? onShare : nil,
                    onDownload: item.map { store.state.actions(for: $0).canDownload } ?? false
                        ? { _ in store.send(.bulkDownloadTapped) }
                        : nil,
                    showsMore: item.map { !store.state.inspectorMoreRows(for: $0).isEmpty } ?? false,
                    more: more
                ))
                .onChange(of: store.directoryPath) { isPeeking = false }
        }
    }

    struct MacItemPeek<More: View>: ViewModifier {
        let item: FileItem?
        let items: [FileItem]
        @Binding var isPeeking: Bool
        let serverURL: URL?
        let shouldShowThumbnails: Bool
        let showsHiddenFiles: Bool
        var isSavedOffline: (FileItem) -> Bool = { _ in false }
        var size: (FileItem) -> Int64? = { $0.isDirectory ? nil : $0.size }
        let onSelect: (FileItem) -> Void
        var onOpen: ((FileItem) -> Void)?
        var onShare: ((FileItem) -> Void)?
        var onDownload: ((FileItem) -> Void)?
        var showsMore = true
        var isListFocused: FocusState<Bool>.Binding?
        @ViewBuilder let more: (FileItem) -> More

        @Environment(MacPeekHost.self) private var host: MacPeekHost?
        @State private var owner = MacPeekOwner()

        func body(content: Content) -> some View {
            content
                .onKeyPress(.space) {
                    guard let isListFocused, isListFocused.wrappedValue, item != nil, serverURL != nil else {
                        return .ignored
                    }
                    isPeeking = true
                    return .handled
                }
                .onChange(of: isPeeking) { _, isOpen in
                    isListFocused?.wrappedValue = !isOpen
                }
                .onChange(of: isPeeking ? item?.id : nil, initial: true) { present() }
                .onDisappear {
                    isPeeking = false
                    host?.hide(owner: ObjectIdentifier(owner))
                }
        }

        private func present() {
            guard isPeeking, let item, let serverURL else {
                isPeeking = false
                host?.hide(owner: ObjectIdentifier(owner))
                return
            }
            host?.show(
                MacPeekCard(
                    item: item,
                    subtitle: subtitle(item),
                    position: position(item),
                    serverURL: serverURL,
                    isSavedOffline: isSavedOffline(item),
                    shouldShowThumbnails: shouldShowThumbnails,
                    showsHiddenFiles: showsHiddenFiles,
                    onOpen: onOpen.map { open in
                        {
                            isPeeking = false
                            open(item)
                        }
                    },
                    onShare: onShare.map { share in { share(item) } },
                    onStep: { step(from: item, by: $0) },
                    onClose: { isPeeking = false },
                    showsMore: showsMore,
                    more: { more(item) }
                )
                .environment(
                    \.macPreviewDownload,
                    onDownload.map { download in MacPreviewDownload { download(item) } }
                ),
                owner: ObjectIdentifier(owner)
            ) { isPeeking = false }
        }

        private func step(from item: FileItem, by offset: Int) {
            guard let index = items.firstIndex(where: { $0.id == item.id }),
                  items.indices.contains(index + offset) else { return }
            onSelect(items[index + offset])
        }

        private func subtitle(_ item: FileItem) -> String {
            let kind = item.isDirectory ? L10n.FileInfo.navigationTitleFolder : item.previewTypeText
            return ([kind] + [size(item).map(FileSizeFormat.string)].compactMap(\.self))
                .joined(separator: MacPeekMetrics.separator)
        }

        private func position(_ item: FileItem) -> String {
            let index = items.firstIndex { $0.id == item.id } ?? .zero
            return L10n.PdfPreview.pageIndicator(index + 1, items.count)
        }
    }

    final class MacPeekOwner {}
#endif
