import ComposableArchitecture
import CoreModels
import Foundation
import Localization

/// Root of the Browse tab: the root folder listing plus a flat push stack of every
/// subfolder drilled into (all `BrowseFeature` instances, same type at every depth).
@Reducer
public struct BrowseTabFeature {
    @ObservableState
    public struct State: Equatable {
        public var root: BrowseFeature.State
        public var path = StackState<BrowseFeature.State>()
        /// Folders left by going back, nearest last, so Forward (⌘]) can reopen them. Any
        /// other navigation clears it, as in Finder.
        public var forwardStack: [BrowseFeature.State] = []
        /// The trash, pushed over the root from its row or a delete's Open Trash.
        @Presents public var trash: TrashFeature.State?

        public init(serverURL: URL) {
            root = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: L10n.Browse.navigationTitle)
        }

        /// The server path of the folder on screen; empty at the volume root.
        public var currentDirectoryPath: String {
            visibleFolder.directoryPath
        }

        /// The folder on screen: the top of the stack, or the root when nothing is pushed.
        var visibleFolder: BrowseFeature.State {
            path.last ?? root
        }
    }

    public enum Action: Equatable, Sendable {
        case root(BrowseFeature.Action)
        case path(StackActionOf<BrowseFeature>)
        case navigateToDirectory(path: String, title: String)
        /// A search hit: opens the folder (or the one holding the file, then selects and opens it) on top
        /// of the folders already open, so Back returns to the previous one.
        case navigateToItem(folder: String, title: String, revealing: String?)
        /// Refetches the root folder and every pushed subfolder currently on the live
        /// navigation stack: sent when the app becomes active again after being backgrounded.
        case syncPathStack
        /// Refetches only the screens (root or pushed) whose `directoryPath` equals `path`.
        /// Sent after an upload finishes so just the affected folder reloads.
        case refreshDirectory(path: String)
        /// Menu bar commands: act on whichever folder is on screen (the top of the stack, or
        /// the root when nothing is pushed).
        case refreshVisibleFolder
        /// A keyboard command on the selection of the folder on screen (iPad Edit menu).
        case commandInVisibleFolder(FolderCommand)
        case newFolderInVisibleFolder
        case newFileInVisibleFolder
        /// Mac ⌘[: leave the visible folder for the screen under it.
        case goBack
        /// Mac ⌘↑: open the folder that contains the visible one.
        case goToEnclosingFolder
        /// Mac ⌘]: reopen the folder last left by going back.
        case goForward
        /// A download landed: recompute the "available offline" badges on every live screen.
        case offlineAvailabilityChanged
        /// Files another app shared in, handed to the topmost screen.
        case receiveSharedFiles([URL])
        /// Opens the trash: pushed over the root on iPhone and iPad, the sidebar's Trash on the Mac.
        case openTrash
        case trash(PresentationAction<TrashFeature.Action>)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case favoritesChanged
            case openDownloadsTapped
            case goToSharedTab
            case uploadRequested([PendingUpload])
            case downloadRequested([FileItem])
            case offlinePinRequested([FileItem])
            case offlineUnpinRequested(path: String)
            case saveRequested([DownloadSaveRequest])
            /// Mac: the trash lives in the sidebar, outside this tab.
            case openTrashTapped
        }
    }

    /// What the iPad Edit menu does to the visible folder's selection.
    public enum FolderCommand: Equatable, Sendable {
        case cut
        case copy
        case paste(keepItemsAfterCopy: Bool)
        case delete
        /// Selects every item, entering select mode first when it is not on.
        case selectAll
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.root, action: \.root) {
            BrowseFeature()
        }
        Reduce { state, action in
            switch action {
            case .goBack:
                state.goBack()
                return .none

            case .goToEnclosingFolder:
                state.goToEnclosingFolder(serverURL: state.root.serverURL)
                return .none

            case .refreshVisibleFolder:
                return Self.sendToVisibleFolder(state, .refreshButtonTapped)

            case let .commandInVisibleFolder(command):
                switch command {
                case .cut:
                    return Self.sendToVisibleFolder(state, .cutSelectionTapped)
                case .copy:
                    return Self.sendToVisibleFolder(state, .copySelectionTapped)
                case let .paste(keepItemsAfterCopy):
                    return Self.sendToVisibleFolder(state, .pasteTapped(keepItemsAfterCopy: keepItemsAfterCopy))
                case .delete:
                    return Self.sendToVisibleFolder(state, .deleteSelectionTapped)
                case .selectAll:
                    let folder = state.visibleFolder
                    let selectAll = Self.sendToVisibleFolder(state, .selectAllTapped)
                    if folder.isSelecting {
                        return selectAll
                    }
                    // As the Select button: a folder with nothing to select stays out of select mode.
                    guard folder.canSelectItems else { return .none }
                    return .concatenate(Self.sendToVisibleFolder(state, .selectModeToggled), selectAll)
                }

            case .newFolderInVisibleFolder:
                // Mirrors the UI: the account root is not a writable folder.
                guard let id = state.path.ids.last,
                      state.path[id: id]?.directoryPath.isEmpty == false
                else { return .none }
                return .send(.path(.element(id: id, action: .newFolderTapped)))

            case .newFileInVisibleFolder:
                guard let id = state.path.ids.last,
                      state.path[id: id]?.directoryPath.isEmpty == false
                else { return .none }
                return .send(.path(.element(id: id, action: .newFileTapped)))

            case .goForward:
                state.goForward()
                return .none

            case let .path(.popFrom(id)):
                state.recordPop(from: id)
                return .none

            case let .root(.delegate(.openFolder(item))):
                state.forwardStack = []
                state.path.append(BrowseNavigation.screen(for: item, serverURL: state.root.serverURL))
                return .none

            case let .root(.delegate(.openPath(path, title))):
                return .send(.navigateToDirectory(path: path, title: title))

            case .root(.delegate(.favoritesChanged)):
                return .send(.delegate(.favoritesChanged))

            case .root(.delegate(.directoryContentsChanged)),
                 .path(.element(id: _, action: .delegate(.directoryContentsChanged))):
                return .send(.syncPathStack)

            case let .receiveSharedFiles(urls):
                return Self.sendToVisibleFolder(state, .receiveSharedFiles(urls))

            case .root(.delegate(.openDownloadsTapped)):
                return .send(.delegate(.openDownloadsTapped))

            case .root(.delegate(.goToSharedTab)),
                 .path(.element(id: _, action: .delegate(.goToSharedTab))):
                return .send(.delegate(.goToSharedTab))

            case let .root(.delegate(.uploadRequested(files))),
                 let .path(.element(id: _, action: .delegate(.uploadRequested(files)))):
                return .send(.delegate(.uploadRequested(files)))

            case let .root(.delegate(.downloadRequested(items))),
                 let .path(.element(id: _, action: .delegate(.downloadRequested(items)))):
                return .send(.delegate(.downloadRequested(items)))

            case let .root(.delegate(.offlinePinRequested(items))),
                 let .path(.element(id: _, action: .delegate(.offlinePinRequested(items)))):
                return .send(.delegate(.offlinePinRequested(items)))

            case let .root(.delegate(.offlineUnpinRequested(path))),
                 let .path(.element(id: _, action: .delegate(.offlineUnpinRequested(path)))):
                return .send(.delegate(.offlineUnpinRequested(path: path)))

            case let .root(.delegate(.saveRequested(requests))),
                 let .path(.element(id: _, action: .delegate(.saveRequested(requests)))):
                return .send(.delegate(.saveRequested(requests)))

            case .root(.delegate(.openTrashTapped)), .path(.element(id: _, action: .delegate(.openTrashTapped))):
                return .send(.openTrash)

            case .openTrash:
                #if os(macOS)
                    return .send(.delegate(.openTrashTapped))
                #else
                    state.forwardStack = []
                    state.path.removeAll()
                    state.trash = TrashFeature.State(serverURL: state.root.serverURL)
                    return .none
                #endif

            case let .trash(.presented(.delegate(.openPath(path, title)))):
                state.trash = nil
                return .send(.navigateToDirectory(path: path, title: title))

            case .trash(.presented(.delegate(.restored))):
                return .send(.syncPathStack)

            case .trash:
                return .none

            case .offlineAvailabilityChanged:
                return .merge(
                    [.send(.root(.computeOfflineAvailability))]
                        + state.path.ids.map { .send(.path(.element(id: $0, action: .computeOfflineAvailability))) }
                )

            case let .path(.element(id: _, action: .delegate(.openFolder(item)))):
                state.forwardStack = []
                state.path.append(BrowseNavigation.screen(for: item, serverURL: state.root.serverURL))
                return .none

            case let .path(.element(id: _, action: .delegate(.openPath(path, title)))):
                return .send(.navigateToDirectory(path: path, title: title))

            case .path(.element(id: _, action: .delegate(.favoritesChanged))):
                return .send(.delegate(.favoritesChanged))

            case .path(.element(id: _, action: .delegate(.openDownloadsTapped))):
                return .send(.delegate(.openDownloadsTapped))

            case let .navigateToDirectory(path, title):
                state.forwardStack = []
                BrowseNavigation.jump(to: path, title: title, serverURL: state.root.serverURL, stack: &state.path)
                return .none

            case let .navigateToItem(folder, title, itemID):
                state.forwardStack = []
                BrowseNavigation.push(to: folder, title: title, serverURL: state.root.serverURL, stack: &state.path)
                guard let itemID else { return .none }
                if let id = state.path.ids.last {
                    state.path[id: id]?.revealItemID = itemID
                } else {
                    state.root.revealItemID = itemID
                }
                return .none

            case .syncPathStack:
                return .merge(
                    [.send(.root(.refreshButtonTapped))]
                        + state.path.ids.map { .send(.path(.element(id: $0, action: .refreshButtonTapped))) }
                )

            case let .refreshDirectory(path):
                var effects: [Effect<Action>] = []
                if state.root.directoryPath == path {
                    effects.append(.send(.root(.refreshButtonTapped)))
                }
                for id in state.path.ids where state.path[id: id]?.directoryPath == path {
                    effects.append(.send(.path(.element(id: id, action: .refreshButtonTapped))))
                }
                return .merge(effects)

            case .root, .path, .delegate:
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            BrowseFeature()
        }
        .ifLet(\.$trash, action: \.trash) {
            TrashFeature()
        }
    }

    /// Hands an action to the folder on screen.
    private static func sendToVisibleFolder(_ state: State, _ action: BrowseFeature.Action) -> Effect<Action> {
        if let id = state.path.ids.last {
            return .send(.path(.element(id: id, action: action)))
        }
        return .send(.root(action))
    }
}
