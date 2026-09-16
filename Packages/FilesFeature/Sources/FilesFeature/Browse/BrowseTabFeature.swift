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

        public init(serverURL: URL) {
            root = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: L10n.Browse.navigationTitle)
        }
    }

    public enum Action: Equatable, Sendable {
        case root(BrowseFeature.Action)
        case path(StackActionOf<BrowseFeature>)
        case navigateToDirectory(path: String, title: String)
        /// Re-fetches the root folder and every pushed subfolder currently on the live
        /// navigation stack — sent when the app becomes active again after being backgrounded.
        case syncPathStack
        /// Refetches only the screens (root or pushed) whose `directoryPath` equals `path`.
        /// Sent after an upload finishes so just the affected folder reloads.
        case refreshDirectory(path: String)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case favoritesChanged
            case openDownloadsTapped
            case goToSharedTab
            case uploadRequested([PendingUpload])
        }
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.root, action: \.root) {
            BrowseFeature()
        }
        Reduce { state, action in
            switch action {
            case let .root(.delegate(.openFolder(item))):
                state.path.append(BrowseNavigation.screen(for: item, serverURL: state.root.serverURL))
                return .none

            case let .root(.delegate(.openPath(path, title))):
                return .send(.navigateToDirectory(path: path, title: title))

            case .root(.delegate(.favoritesChanged)):
                return .send(.delegate(.favoritesChanged))

            case .root(.delegate(.directoryContentsChanged)),
                 .path(.element(id: _, action: .delegate(.directoryContentsChanged))):
                return .send(.syncPathStack)

            case .root(.delegate(.openDownloadsTapped)):
                return .send(.delegate(.openDownloadsTapped))

            case .root(.delegate(.goToSharedTab)),
                 .path(.element(id: _, action: .delegate(.goToSharedTab))):
                return .send(.delegate(.goToSharedTab))

            case let .root(.delegate(.uploadRequested(files))),
                 let .path(.element(id: _, action: .delegate(.uploadRequested(files)))):
                return .send(.delegate(.uploadRequested(files)))

            case let .path(.element(id: _, action: .delegate(.openFolder(item)))):
                state.path.append(BrowseNavigation.screen(for: item, serverURL: state.root.serverURL))
                return .none

            case let .path(.element(id: _, action: .delegate(.openPath(path, title)))):
                return .send(.navigateToDirectory(path: path, title: title))

            case .path(.element(id: _, action: .delegate(.favoritesChanged))):
                return .send(.delegate(.favoritesChanged))

            case .path(.element(id: _, action: .delegate(.openDownloadsTapped))):
                return .send(.delegate(.openDownloadsTapped))

            case let .navigateToDirectory(path, title):
                BrowseNavigation.jump(to: path, title: title, serverURL: state.root.serverURL, stack: &state.path)
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
    }
}
