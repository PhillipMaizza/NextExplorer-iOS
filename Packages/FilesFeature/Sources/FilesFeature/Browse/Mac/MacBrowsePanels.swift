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

        func body(content: Content) -> some View {
            content
                .modifier(MacBrowseInspector(
                    screen: store,
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
        }

        private func moreMenu(for item: FileItem) -> some View {
            MacInspectorMoreMenu(store: store, item: item) { toastMessage = .failure($0) }
        }
    }
#endif
