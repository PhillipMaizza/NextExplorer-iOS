import ComposableArchitecture
import CoreModels
import Foundation
import Localization
import NetworkClient

@Reducer
public struct MainTabFeature {
    public enum Tab: Equatable, Hashable, Sendable {
        case browse, favorites, shared, downloads, settings
    }

    /// The "Upload complete" toast shown app-wide once the queue drains. `openDestination` is
    /// the folder to jump to when the user taps "Open": `nil` hides that button (they're
    /// already looking at it, or nothing succeeded).
    public struct UploadToast: Equatable, Sendable {
        public var message: String
        public var openDestination: String?
    }

    @ObservableState
    public struct State: Equatable {
        public var selectedTab: Tab = .browse
        /// The Mac Go to Folder dialog is open.
        public var isGoToFolderPresented = false
        /// Folders opened in Browse this session, newest first, for the Mac's Go ▸ Recent
        /// Folders and Dock menu. Session state, so it never outlives a sign out or an account
        /// switch.
        public var recentFolders: [String] = []
        public var browse: BrowseTabFeature.State
        public var favorites: FavoritesFeature.State
        public var shared: SharedFeature.State
        public var downloads = OfflineTabFeature.State()
        public var settings: SettingsFeature.State
        public var uploads: UploadsFeature.State
        public var downloadQueue: DownloadQueueFeature.State
        /// The offline download engine, a session lifetime sibling so its long running download
        /// effect survives the user leaving the Settings screen that started it.
        public var offline: OfflineDownloadsFeature.State
        /// What the Offline tab lists: every pinned file and folder with its size.
        public var offlineManage = OfflineManageFeature.State()
        /// Shared offline progress, reset when a fresh session mounts so a previous account's
        /// finished run never lingers on the new account's Settings screen.
        @Shared(.inMemory(OfflineDownloadProgress.sharedKey)) public var offlineProgress = OfflineDownloadProgress()
        /// A run stored new files while another section was on screen: the Offline tab and sidebar row
        /// show a dot until Offline is opened. Held in memory, so it ends with the session.
        public var hasUnseenOfflineFiles = false
        @Shared(.inMemory(SharedFileInbox.sharedKey)) public var sharedFileInbox: [URL] = []
        public var uploadToast: UploadToast?
        /// The "saved to Downloads" confirmation once the download queue drains.
        public var downloadToast: String?
        /// iPhone and iPad: staged files waiting for the Save to Files panel.
        public var pendingExportURLs: [URL] = []
        #if os(macOS)
            /// Where the last Mac save landed, revealed by the confirmation's Show in Finder.
            public var lastSavedDownloadURL: URL?
            /// The latest folder change, for the extra Browse windows to reload.
            public var folderWindowSync = FolderWindowSync()
        #endif

        public init(serverURL: URL, user: User) {
            browse = BrowseTabFeature.State(serverURL: serverURL)
            favorites = FavoritesFeature.State(serverURL: serverURL)
            downloads = OfflineTabFeature.State(serverURL: serverURL)
            shared = SharedFeature.State(serverURL: serverURL)
            settings = SettingsFeature.State(serverURL: serverURL, user: user)
            uploads = UploadsFeature.State(serverURL: serverURL)
            downloadQueue = DownloadQueueFeature.State(serverURL: serverURL)
            offline = OfflineDownloadsFeature.State(serverURL: serverURL)
        }

        /// An upload or download the user started is still running, so quitting would stop it.
        /// Offline sync is left out: it resumes on its own.
        public var hasTransfersInFlight: Bool {
            uploads.isActive || downloadQueue.isActive
        }

        /// The folder currently on screen in the Browse tab (root or the deepest pushed
        /// subfolder).
        var currentBrowseDirectory: String {
            browse.path.last?.directoryPath ?? browse.root.directoryPath
        }
    }

    public enum Action: Sendable {
        case tabSelected(Tab)
        /// Mac menu bar commands: refresh whatever the selected tab shows, and create a folder
        /// in the visible Browse folder (only while Browse is the selected tab).
        case refreshSelectedTab
        case newFolderRequested
        case newFileRequested
        /// Mac Go menu: Back (⌘[), Enclosing Folder (⌘↑), Forward (⌘]) and Go to Folder (⇧⌘G).
        case backRequested
        case enclosingFolderRequested
        case forwardRequested
        case goToFolderPrompted
        case goToFolderDismissed
        case goToFolderRequested(String)
        case recentFoldersCleared
        #if os(macOS)
            /// An extra Browse window changed these folders; the main window and the other
            /// windows reload what they show of them.
            case folderWindowChanged(FolderContentsChange, origin: UUID)
        #endif
        /// Sent when the scene becomes active again after being backgrounded: `BrowseTabFeature`
        /// re-fetches the current folder and every pushed subfolder, since `BrowseFeature.onAppear`
        /// deliberately no-ops once a folder already has items loaded.
        case appBecameActive
        /// Long-lived subscription to reachability, started once from the view's `.task`.
        case observeConnectivity
        /// Drains `SharedFileInbox` into an upload review on the Browse tab.
        case sharedFilesArrived
        /// The connection came back: refresh the list tabs so their offline "saved copy"
        /// banners clear and they show live data without a manual pull.
        case connectivityRestored
        case browse(BrowseTabFeature.Action)
        case favorites(FavoritesFeature.Action)
        case shared(SharedFeature.Action)
        case downloads(OfflineTabFeature.Action)
        case settings(SettingsFeature.Action)
        case uploads(UploadsFeature.Action)
        case downloadQueue(DownloadQueueFeature.Action)
        case offline(OfflineDownloadsFeature.Action)
        case offlineManage(OfflineManageFeature.Action)
        case openUploadedLocation(String)
        case dismissUploadToast
        case openDownloadsTab
        case dismissDownloadToast
        /// The Save to Files panel closed; `didSave` is false when the user cancelled it.
        case deviceExportFinished(didSave: Bool)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case signOutButtonTapped
            /// Multi-server account switcher (Settings): activate, remove, or add another account.
            case switchAccount(String)
            case removeAccount(String)
            case addAccountRequested
        }
    }

    @Dependency(\.connectivity) var connectivity
    @Dependency(\.deviceSaver) var deviceSaver
    @Dependency(\.clientCertificateClient) var clientCertificateClient

    private enum CancelID { case connectivity }

    public init() {}

    /// The Mac builds one split view per section, and a section's folder stack writes an empty
    /// path back as it is torn down. That pop is not the user's (Back only works on screen), so it
    /// is dropped and the open folder survives a trip through another section.
    static func isSectionTeardownPop(_ action: Action, selectedTab: Tab) -> Bool {
        #if os(macOS)
            switch action {
            case .browse(.path(.popFrom)): selectedTab != .browse
            case .favorites(.path(.popFrom)): selectedTab != .favorites
            default: false
            }
        #else
            false
        #endif
    }

    public var body: some ReducerOf<Self> {
        // Combined so the Recent Folders `onChange` also sees navigation done inside Browse.
        CombineReducers {
            let browse = Scope<State, Action, BrowseTabFeature>(state: \.browse, action: \.browse) {
                BrowseTabFeature()
            }
            let favorites = Scope<State, Action, FavoritesFeature>(state: \.favorites, action: \.favorites) {
                FavoritesFeature()
            }
            Reduce { state, action in
                guard !Self.isSectionTeardownPop(action, selectedTab: state.selectedTab) else { return .none }
                return .merge(
                    browse._reduce(into: &state, action: action),
                    favorites._reduce(into: &state, action: action)
                )
            }
            Scope(state: \.shared, action: \.shared) {
                SharedFeature()
            }
            Scope(state: \.downloads, action: \.downloads) {
                OfflineTabFeature()
            }
            Scope(state: \.settings, action: \.settings) {
                SettingsFeature()
            }
            Scope(state: \.uploads, action: \.uploads) {
                UploadsFeature()
            }
            Scope(state: \.downloadQueue, action: \.downloadQueue) {
                DownloadQueueFeature()
            }
            Scope(state: \.offline, action: \.offline) {
                OfflineDownloadsFeature()
            }
            Scope(state: \.offlineManage, action: \.offlineManage) {
                OfflineManageFeature()
            }
            Reduce { state, action in
                switch action {
                case let .tabSelected(tab):
                    state.selectedTab = tab
                    return .none

                case .refreshSelectedTab:
                    switch state.selectedTab {
                    case .browse: return .send(.browse(.refreshVisibleFolder))
                    case .favorites: return .send(.favorites(.refreshButtonTapped))
                    case .shared: return .send(.shared(.refreshRequested))
                    case .downloads: return .send(.downloads(.refreshButtonTapped))
                    case .settings: return .none
                    }

                case .newFolderRequested:
                    guard state.selectedTab == .browse else { return .none }
                    return .send(.browse(.newFolderInVisibleFolder))

                case .newFileRequested:
                    guard state.selectedTab == .browse else { return .none }
                    return .send(.browse(.newFileInVisibleFolder))

                case .backRequested:
                    switch state.selectedTab {
                    case .browse: return .send(.browse(.goBack))
                    case .favorites: return .send(.favorites(.goBack))
                    case .shared, .downloads, .settings: return .none
                    }

                case .forwardRequested:
                    switch state.selectedTab {
                    case .browse: return .send(.browse(.goForward))
                    case .favorites: return .send(.favorites(.goForward))
                    case .shared, .downloads, .settings: return .none
                    }

                case .goToFolderPrompted:
                    state.isGoToFolderPresented = true
                    return .none

                case .goToFolderDismissed:
                    state.isGoToFolderPresented = false
                    return .none

                case let .goToFolderRequested(rawPath):
                    state.isGoToFolderPresented = false
                    guard let path = Self.goToFolderPath(rawPath) else { return .none }
                    state.selectedTab = .browse
                    return .send(.browse(.navigateToDirectory(path: path, title: (path as NSString).lastPathComponent)))

                case .enclosingFolderRequested:
                    switch state.selectedTab {
                    case .browse: return .send(.browse(.goToEnclosingFolder))
                    case .favorites: return .send(.favorites(.goToEnclosingFolder))
                    case .shared, .downloads, .settings: return .none
                    }

                case .sharedFilesArrived:
                    let urls = state.sharedFileInbox
                    guard !urls.isEmpty else { return .none }
                    state.$sharedFileInbox.withLock { $0 = [] }
                    state.selectedTab = .browse
                    return .send(.browse(.receiveSharedFiles(urls)))

                case let .browse(.delegate(.uploadRequested(files))),
                     let .favorites(.delegate(.uploadRequested(files))),
                     let .downloads(.delegate(.uploadRequested(files))):
                    return .send(.uploads(.enqueue(files)))

                case let .browse(.delegate(.downloadRequested(items))),
                     let .favorites(.delegate(.downloadRequested(items))),
                     let .downloads(.delegate(.downloadRequested(items))):
                    return .send(.downloadQueue(.enqueue(items)))

                case let .browse(.delegate(.saveRequested(requests))),
                     let .favorites(.delegate(.saveRequested(requests))),
                     let .downloads(.delegate(.saveRequested(requests))):
                    return .send(.downloadQueue(.enqueueSaves(requests)))

                case .downloadQueue(.delegate(.itemSaved)):
                    return .merge(
                        .send(.downloads(.refreshButtonTapped)),
                        .send(.browse(.offlineAvailabilityChanged)),
                        .send(.favorites(.offlineAvailabilityChanged)),
                        .send(.downloads(.offlineAvailabilityChanged))
                    )

                case let .downloadQueue(.delegate(.queueFinished(summary))):
                    // Failures stay on the persistent failed bar with its own Retry.
                    guard summary.failedCount == 0, summary.savedCount > 0 else { return .none }
                    #if os(macOS)
                        // A Mac save lands where the user chose in Finder, not in a Downloads tab.
                        if let savedURL = summary.lastSavedURL {
                            state.lastSavedDownloadURL = savedURL
                            state.downloadToast = Self.macSavedMessage(
                                count: summary.savedCount,
                                lastSavedURL: savedURL
                            )
                            return .none
                        }
                    #endif
                    #if os(macOS)
                        state.downloadToast = summary.savedCount == 1
                            ? L10n.DownloadQueue.savedOne
                            : L10n.DownloadQueue.savedMany(summary.savedCount)
                    #endif
                    return .none

                case .openDownloadsTab:
                    state.downloadToast = nil
                    state.downloadQueue.isSheetPresented = false
                    state.selectedTab = .downloads
                    return .send(.downloads(.refreshButtonTapped))

                case .dismissDownloadToast:
                    state.downloadToast = nil
                    return .none

                case let .uploads(.delegate(.queueFinished(summary))):
                    // Refetch only the folders an upload actually landed in, and only where they
                    // are on screen: `refreshDirectory` does nothing for a path nothing is showing.
                    var effects: [Effect<Action>] = []
                    for path in summary.changedPaths {
                        effects.append(.send(.browse(.refreshDirectory(path: path))))
                        effects.append(.send(.favorites(.refreshDirectory(path: path))))
                    }
                    // Failures are surfaced by the persistent failed bar (with its own Retry), so
                    // the toast is only the all-succeeded confirmation.
                    if summary.failedCount == 0, summary.uploadedCount > 0 {
                        let message = summary.uploadedCount == 1
                            ? L10n.Uploads.complete
                            : L10n.Uploads.completeMany(summary.uploadedCount)
                        let alreadyThere = state.selectedTab == .browse
                            && summary.lastDestination == state.currentBrowseDirectory
                        state.uploadToast = UploadToast(
                            message: message,
                            openDestination: alreadyThere ? nil : summary.lastDestination
                        )
                    }
                    return .merge(effects)

                case let .openUploadedLocation(destination):
                    state.uploadToast = nil
                    state.selectedTab = .browse
                    let title = destination.isEmpty
                        ? L10n.Browse.navigationTitle
                        : (destination as NSString).lastPathComponent
                    return .send(.browse(.navigateToDirectory(path: destination, title: title)))

                case .dismissUploadToast:
                    state.uploadToast = nil
                    return .none

                case .appBecameActive:
                    return .merge(
                        .send(.browse(.syncPathStack)),
                        .send(.favorites(.syncPathStack)),
                        .send(.uploads(.appResumed)),
                        // Check the pinned folders for new files each time the app comes forward.
                        .send(.offline(.autoSync(force: false)))
                    )

                case .observeConnectivity:
                    // Runs once when this session's shell mounts. The progress is shared in memory and
                    // outlives the shell: a run cut off by a sign out leaves its last file name in it,
                    // which the next account must never see. No run of this session has started yet,
                    // so it is cleared whatever it says, then the pinned folders are checked.
                    state.$offlineProgress.withLock { $0 = OfflineDownloadProgress() }
                    // First value is the current state (ignored); refresh only on a real
                    // offline -> online transition.
                    let connectivity = connectivity
                    let clientCertificateClient = clientCertificateClient
                    let certificateOrigin = ClientCertificateOrigin(url: state.browse.root.serverURL)
                    return .merge(
                        .send(.offline(.autoSync(force: false))),
                        // Loads this server's client certificate record off the main actor once, so
                        // the video views can check for it from memory when they open.
                        .run { _ in
                            if let certificateOrigin {
                                _ = await clientCertificateClient.summary(certificateOrigin)
                            }
                        },
                        .run { send in
                            var wasOnline = true
                            for await online in connectivity.events() {
                                defer { wasOnline = online }
                                if online, !wasOnline {
                                    await send(.connectivityRestored)
                                }
                            }
                        }
                        .cancellable(id: CancelID.connectivity, cancelInFlight: true)
                    )

                case .connectivityRestored:
                    // Refresh every list tab (each is cancel-in-flight, so this is cheap) so no tab
                    // is left showing a stale offline copy after the connection returns. Both tabs
                    // that own a browse stack refresh their root and every pushed subfolder, matching
                    // `appBecameActive`; Favorites needs `syncPathStack` too or a folder pushed inside
                    // the Favorites tab keeps its "saved copy" banner after the connection is back.
                    return .merge(
                        .send(.browse(.syncPathStack)),
                        .send(.favorites(.refreshButtonTapped)),
                        .send(.favorites(.syncPathStack)),
                        .send(.shared(.refreshRequested)),
                        // Back online: pull any files added to pinned folders while offline.
                        .send(.offline(.autoSync(force: true)))
                    )

                case .browse(.delegate(.favoritesChanged)),
                     .favorites(.delegate(.favoritesChanged)),
                     .downloads(.delegate(.favoritesChanged)):
                    return .send(.favorites(.refreshButtonTapped))

                case .browse(.delegate(.openDownloadsTapped)), .favorites(.delegate(.openDownloadsTapped)):
                    state.selectedTab = .downloads
                    return .send(.downloads(.refreshButtonTapped))

                case .browse(.delegate(.goToSharedTab)),
                     .favorites(.delegate(.goToSharedTab)),
                     .downloads(.delegate(.goToSharedTab)):
                    state.selectedTab = .shared
                    return .send(.shared(.refreshRequested))

                case .settings(.delegate(.signOutButtonTapped)):
                    return .send(.delegate(.signOutButtonTapped))

                case let .settings(.delegate(.switchAccount(id))):
                    return .send(.delegate(.switchAccount(id)))

                case let .settings(.delegate(.removeAccount(id))):
                    return .send(.delegate(.removeAccount(id)))

                case .settings(.delegate(.addAccountRequested)):
                    return .send(.delegate(.addAccountRequested))

                case .settings(.delegate(.allDownloadsRemoved)):
                    state.downloads.downloads = []
                    return .none

                case let .settings(.delegate(.startOfflineDownload(items))):
                    return .send(.offline(.startDownload(items)))

                case .settings(.delegate(.cancelOfflineDownload)):
                    return .send(.offline(.cancelTapped))

                case .settings(.delegate(.resyncOffline)):
                    return .send(.offline(.resyncTapped))

                case .settings(.delegate(.removeOfflineFiles)):
                    return .send(.offline(.removeAllOfflineTapped))

                case .settings(.delegate(.offlineRootsRemoved)):
                    return .send(.offline(.pinnedRootsRemoved))

                case .recentFoldersCleared:
                    state.recentFolders = []
                    return .none

                #if os(macOS)
                    case let .folderWindowChanged(change, origin):
                        state.folderWindowSync.broadcast(change, from: origin)
                        return .merge(
                            BrowseTabFeature.refresh(for: change).map(Action.browse),
                            FavoritesFeature.refresh(for: change).map(Action.favorites)
                        )
                #endif

                case .browse, .favorites, .shared, .downloads, .settings, .uploads, .downloadQueue, .offline,
                     .offlineManage, .delegate,
                     .deviceExportFinished:
                    return .none
                }
            }
            Reduce<State, Action> { state, action -> Effect<Action> in
                switch action {
                case let .downloadQueue(.delegate(.queueFinished(summary))):
                    return Self.finishDeviceSave(summary, state: &state)
                case .tabSelected(.downloads), .offline(.prepared), .offline(.completed),
                     .offline(.waitingForNetwork), .offline(.failed),
                     .offline(.unpinFinished):
                    if case .offline(.completed) = action,
                       state.selectedTab != .downloads,
                       state.offlineProgress.filesDone > 0
                    {
                        state.hasUnseenOfflineFiles = true
                    }
                    // The Offline tab lists what is pinned, which these change after it first appeared.
                    return .send(.offlineManage(.onAppear))
                case .offlineManage(.delegate(.changed)):
                    return .merge(
                        .send(.offline(.pinnedRootsRemoved)),
                        .send(.browse(.offlineAvailabilityChanged)),
                        .send(.favorites(.offlineAvailabilityChanged)),
                        .send(.downloads(.offlineAvailabilityChanged))
                    )
                case let .deviceExportFinished(didSave):
                    let staged = state.pendingExportURLs
                    state.pendingExportURLs = []
                    deviceSaver.discard(staged)
                    if didSave {
                        state.downloadToast = L10n.DownloadQueue.savedToDevice
                    }
                    return .none
                case let .browse(.delegate(.offlinePinRequested(items))),
                     let .favorites(.delegate(.offlinePinRequested(items))),
                     let .downloads(.delegate(.offlinePinRequested(items))):
                    return .send(.offline(.startDownload(items)))
                case let .browse(.delegate(.offlineUnpinRequested(path))),
                     let .favorites(.delegate(.offlineUnpinRequested(path))),
                     let .downloads(.delegate(.offlineUnpinRequested(path))):
                    return .send(.offline(.unpinTapped(path: path)))
                default:
                    return .none
                }
            }
            #if os(macOS)
                Reduce { state, action in
                    Self.syncFolderWindows(&state, after: action)
                }
            #endif
        }
        .onChange(of: \.selectedTab) { _, tab in
            Reduce { state, _ in
                // However Offline was reached (a tap, a menu, a toast), its new files are now seen.
                if tab == .downloads {
                    state.hasUnseenOfflineFiles = false
                }
                return .none
            }
        }
        .onChange(of: \.browse.currentDirectoryPath) { _, path in
            Reduce { state, _ in
                guard !path.isEmpty else { return .none }
                state.recentFolders.removeAll { $0 == path }
                state.recentFolders.insert(path, at: 0)
                state.recentFolders = Array(state.recentFolders.prefix(Self.recentFoldersLimit))
                return .none
            }
        }
    }

    /// What a drained Save to Device queue does next: the Save to Files panel for staged files,
    /// otherwise a confirmation. The Mac saves where its panel said, so it has nothing to add.
    private static func finishDeviceSave(
        _ summary: DownloadQueueFeature.FinishSummary,
        state: inout State
    ) -> Effect<Action> {
        #if os(macOS)
            return .none
        #else
            if !summary.exportURLs.isEmpty {
                state.pendingExportURLs += summary.exportURLs
            } else if summary.failedCount == 0, summary.photosCount > 0 {
                state.downloadToast = L10n.DownloadQueue.savedToPhotos
            }
            return .none
        #endif
    }

    /// As many as Finder's Recent Folders menu keeps by default.
    static let recentFoldersLimit = 10

    /// A typed Go to Folder path as the server names it, without surrounding slashes or spaces;
    /// `nil` when nothing is left.
    static func goToFolderPath(_ rawPath: String) -> String? {
        let path = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "/ ").union(.whitespacesAndNewlines))
        return path.isEmpty ? nil : path
    }
}

extension MainTabFeature.State {
    /// The Available Offline pill shows while a run works or after one failed.
    var isOfflineBarVisible: Bool {
        if offlineProgress.isActive {
            return true
        }
        if case .failed = offlineProgress.phase {
            return true
        }
        return false
    }
}
