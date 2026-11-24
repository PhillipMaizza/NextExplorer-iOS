#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import SwiftUI

    struct ArchivePeekPresenter: ViewModifier {
        let store: StoreOf<BrowseFeature>
        @Environment(MacPeekHost.self) private var host: MacPeekHost?

        private var owner: ObjectIdentifier {
            ObjectIdentifier(ArchiveBrowserFeature.self)
        }

        private var archive: FileItem? {
            store.isArchivePeek ? store.previewItem : nil
        }

        func body(content: Content) -> some View {
            content
                .onChange(of: archive?.id, initial: true) { present() }
                .onDisappear { host?.hide(owner: owner) }
        }

        private func present() {
            guard let archive else {
                host?.hide(owner: owner)
                return
            }
            let browse = store
            let dismiss: () -> Void = { browse.send(.previewDismissed) }
            let card = ArchivePeekCard(
                store: Store(initialState: ArchiveBrowserFeature.State(archive: archive, serverURL: browse.serverURL)) {
                    ArchiveBrowserFeature()
                },
                onExtract: { paths in
                    dismiss()
                    browse.send(.extractTapped(archive, entryPaths: paths))
                },
                onClose: dismiss
            )
            host?.show(card, owner: owner, onClose: dismiss)
        }
    }
#endif
