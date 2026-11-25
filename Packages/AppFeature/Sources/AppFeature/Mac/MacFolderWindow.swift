#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesFeature
    import SwiftUI

    private enum Metrics {
        static let minWidth: CGFloat = 640
        static let minHeight: CGFloat = 420
    }

    /// Content of an extra Mac Browse window or tab. It borrows the main window's session and
    /// hands uploads, favorites changes and tab jumps back to the main store. It closes itself
    /// on sign out or an account switch, so no window keeps showing a previous account's files.
    public struct MacFolderWindow: View {
        let route: FolderWindowRoute
        let mainStore: StoreOf<AppFeature>

        @State private var store: StoreOf<FolderWindowFeature>?
        @State private var accountID: String?
        /// Tells this window's own changes apart when the main store broadcasts them back.
        @State private var windowID = UUID()
        @Environment(\.dismiss) private var dismiss

        public init(route: FolderWindowRoute, mainStore: StoreOf<AppFeature>) {
            self.route = route
            self.mainStore = mainStore
        }

        public var body: some View {
            Group {
                if let store {
                    // Inside the window's own state, so a language change keeps its folders.
                    FolderWindowView(store: store)
                        .followsAppLanguage()
                } else {
                    Color.clear
                }
            }
            .environment(\.horizontalSizeClass, .regular)
            .frame(minWidth: Metrics.minWidth, minHeight: Metrics.minHeight)
            .onAppear(perform: start)
            .onChange(of: mainStore.currentAccountID) { _, newValue in
                if newValue == nil || newValue != accountID {
                    dismiss()
                }
            }
            .onChange(of: folderWindowSync) { _, sync in
                guard let sync, sync.origin != windowID else { return }
                store?.send(.otherWindowChanged(sync.change))
            }
        }

        private var folderWindowSync: FolderWindowSync? {
            guard case let .authenticated(session) = mainStore.destination else { return nil }
            return session.mainTab.folderWindowSync
        }

        private func start() {
            guard store == nil else { return }
            guard case let .authenticated(session) = mainStore.destination,
                  let account = mainStore.currentAccountID
            else {
                dismiss()
                return
            }
            accountID = account
            let mainStore = mainStore
            let windowID = windowID
            let windowStore = Store(initialState: FolderWindowFeature
                .State(serverURL: session.mainTab.browse.root.serverURL))
            {
                FolderWindowFeature { forwarded in
                    await MainActor.run {
                        guard case .authenticated = mainStore.destination else { return }
                        let action: MainTabFeature.Action = switch forwarded {
                        case let .browse(delegate): .browse(.delegate(delegate))
                        case let .folderChanged(change): .folderWindowChanged(change, origin: windowID)
                        }
                        mainStore.send(.destination(.authenticated(.mainTab(action))))
                    }
                }
            }
            if !route.path.isEmpty {
                windowStore.send(.browse(.navigateToDirectory(path: route.path, title: route.title)))
            }
            store = windowStore
        }
    }

    #Preview("Folder") {
        MacFolderWindow(route: FolderWindowRoute(path: "Documents", title: "Documents"), mainStore: .previewSignedIn())
    }
#endif
