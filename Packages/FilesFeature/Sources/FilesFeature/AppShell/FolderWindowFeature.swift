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
            /// Another window changed folders this one may show.
            case otherWindowChanged(FolderContentsChange)
            /// Go ▸ Go to Folder… with this window in front.
            case goToFolderRequested(String)
        }

        /// What this window hands the main window.
        public enum Forwarded: Equatable, Sendable {
            case browse(BrowseTabFeature.Action.Delegate)
            /// A change finished here, for the main window and the other windows to reload.
            case folderChanged(FolderContentsChange)
        }

        private let forward: @Sendable (Forwarded) async -> Void

        public init(forward: @escaping @Sendable (Forwarded) async -> Void) {
            self.forward = forward
        }

        public var body: some ReducerOf<Self> {
            Scope(state: \.browse, action: \.browse) {
                BrowseTabFeature()
            }
            Reduce { state, action in
                let forward = forward
                switch action {
                case let .browse(.delegate(delegate)):
                    return .run { _ in await forward(.browse(delegate)) }
                case let .browse(browseAction):
                    guard let change = BrowseTabFeature.folderContentsChange(after: browseAction, in: state.browse) else { return .none }
                    return .run { _ in await forward(.folderChanged(change)) }
                case let .otherWindowChanged(change):
                    return BrowseTabFeature.refresh(for: change).map(Action.browse)
                case let .goToFolderRequested(rawPath):
                    guard let path = MainTabFeature.goToFolderPath(rawPath) else { return .none }
                    return .send(.browse(.navigateToDirectory(path: path, title: (path as NSString).lastPathComponent)))
                }
            }
        }
    }

    public struct FolderWindowView: View {
        let store: StoreOf<FolderWindowFeature>
        @State private var isGoToFolderPresented = false

        public init(store: StoreOf<FolderWindowFeature>) {
            self.store = store
        }

        public var body: some View {
            BrowseTabView(store: store.scope(state: \.browse, action: \.browse))
                .windowTitle(store.browse.path.last?.title ?? store.browse.root.title)
                .focusedSceneValue(\.folderWindowCommands, FolderWindowCommands(
                    send: { store.send(.browse($0)) },
                    showGoToFolder: { isGoToFolderPresented = true }
                ))
                .sheet(isPresented: $isGoToFolderPresented) {
                    MacGoToFolderSheet(
                        onGo: { path in
                            isGoToFolderPresented = false
                            store.send(.goToFolderRequested(path))
                        },
                        onCancel: { isGoToFolderPresented = false }
                    )
                }
        }
    }

    /// The Go menu and New Folder for an extra Browse window, so with that window in front they
    /// act on it rather than on the main window.
    public struct FolderWindowCommands {
        let send: (BrowseTabFeature.Action) -> Void
        var showGoToFolder: () -> Void = {}

        public func back() {
            send(.goBack)
        }

        public func forward() {
            send(.goForward)
        }

        public func enclosingFolder() {
            send(.goToEnclosingFolder)
        }

        public func newFolder() {
            send(.newFolderInVisibleFolder)
        }

        public func newFile() {
            send(.newFileInVisibleFolder)
        }

        public func goToFolder() {
            showGoToFolder()
        }
    }

    public extension FocusedValues {
        @Entry var folderWindowCommands: FolderWindowCommands?
    }

    #Preview {
        FolderWindowView(store: Store(initialState: FolderWindowFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")
        )) { FolderWindowFeature(forward: { _ in }) } withDependencies: { $0.filesClient = .previewValue })
            .previewCanvas(.window)
    }
#endif
