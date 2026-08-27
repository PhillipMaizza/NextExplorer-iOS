import ComposableArchitecture
import CoreModels
import Foundation

/// Root of the Browse tab: the root folder listing plus a flat push stack of every
/// subfolder drilled into (all `BrowseFeature` instances, same type at every depth).
@Reducer
public struct BrowseTabFeature {
    @ObservableState
    public struct State: Equatable {
        public var root: BrowseFeature.State
        public var path = StackState<BrowseFeature.State>()

        public init(serverURL: URL) {
            self.root = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        }
    }

    public enum Action: Equatable, Sendable {
        case root(BrowseFeature.Action)
        case path(StackActionOf<BrowseFeature>)
        case navigateToDirectory(path: String, title: String)
        /// Re-fetches the root folder and every pushed subfolder currently on the live
        /// navigation stack — sent when the app becomes active again after being backgrounded.
        case syncPathStack
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case favoritesChanged
            case openDownloadsTapped
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

            case .root(.delegate(.openDownloadsTapped)):
                return .send(.delegate(.openDownloadsTapped))

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

            case .root, .path, .delegate:
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            BrowseFeature()
        }
    }
}
