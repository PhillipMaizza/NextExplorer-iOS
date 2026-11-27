#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import SwiftUI

    struct MacBrowsePanels: ViewModifier {
        let store: StoreOf<BrowseFeature>
        @Binding var isPeeking: Bool
        @Binding var shareTarget: FileItem?
        @Binding var toastMessage: DSToastMessage?
        let onOpen: (FileItem) -> Void

        @State private var versions = VersionsModel()

        func body(content: Content) -> some View {
            content
                .modifier(MacBrowseInspector(
                    screen: store,
                    versions: versions,
                    onOpen: onOpen,
                    onShare: { shareTarget = $0 },
                    more: moreMenu
                ))
                .modifier(MacPeekOverlay(
                    store: store,
                    isPeeking: $isPeeking,
                    onOpen: onOpen,
                    onShare: { shareTarget = $0 },
                    more: moreMenu
                ))
                .modifier(MacVersionsDialogs(model: versions))
                .environment(versions)
                .task(id: versionsTarget?.id) {
                    guard let item = versionsTarget else { return }
                    versions.onFilesChanged = { store.send(.refreshButtonTapped) }
                    versions.onMenuFailure = { toastMessage = .failure($0) }
                    await versions.load(
                        item: item,
                        serverURL: store.serverURL,
                        account: store.cacheScope,
                        settle: MacInspectorMetrics.followDelay
                    )
                }
        }

        private var versionsTarget: FileItem? {
            if let item = store.infoItem {
                return item.isDirectory ? nil : item
            }
            let selected = store.state.selectedItems
            guard selected.count == 1, let item = selected.first, !item.isDirectory else { return nil }
            return item
        }

        private func moreMenu(for item: FileItem) -> some View {
            MacInspectorMoreMenu(store: store, item: item) { toastMessage = .failure($0) }
        }
    }
#endif
