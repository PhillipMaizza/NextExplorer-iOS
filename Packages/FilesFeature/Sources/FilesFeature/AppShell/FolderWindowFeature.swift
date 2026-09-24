#if os(macOS)
    import ComposableArchitecture
    import DesignSystem
    import SwiftUI

    /// A Mac Browse window or tab: its own folder navigation, while everything app wide (the
    /// upload queue, favorites, offline sync, the session) stays with the main window. Anything
    /// the browser would hand up to the app shell is forwarded there instead.
    @Reducer
    public struct FolderWindowFeature {
        @ObservableState
        public struct State: Equatable {
            public var browse: BrowseTabFeature.State

            public init(serverURL: URL) {
                browse = BrowseTabFeature.State(serverURL: serverURL)
            }
        }

        public enum Action {
            case browse(BrowseTabFeature.Action)
        }

        private let forward: @Sendable (BrowseTabFeature.Action.Delegate) async -> Void

        public init(forward: @escaping @Sendable (BrowseTabFeature.Action.Delegate) async -> Void) {
            self.forward = forward
        }

        public var body: some ReducerOf<Self> {
            Scope(state: \.browse, action: \.browse) {
                BrowseTabFeature()
            }
            Reduce { _, action in
                guard case let .browse(.delegate(delegate)) = action else { return .none }
                let forward = forward
                return .run { _ in await forward(delegate) }
            }
        }
    }

    public struct FolderWindowView: View {
        let store: StoreOf<FolderWindowFeature>

        public init(store: StoreOf<FolderWindowFeature>) {
            self.store = store
        }

        public var body: some View {
            BrowseTabView(store: store.scope(state: \.browse, action: \.browse))
                .windowTitle(store.browse.path.last?.title ?? store.browse.root.title)
        }
    }
#endif
