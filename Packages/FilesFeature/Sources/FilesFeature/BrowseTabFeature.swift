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
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.root, action: \.root) {
            BrowseFeature()
        }
        Reduce { state, action in
            switch action {
            case let .root(.delegate(.openFolder(item))):
                state.path.append(BrowseFeature.State(serverURL: state.root.serverURL, directoryPath: item.id, title: item.name))
                return .none

            case let .root(.delegate(.openPath(path, title))):
                return .send(.navigateToDirectory(path: path, title: title))

            case let .path(.element(id: _, action: .delegate(.openFolder(item)))):
                state.path.append(BrowseFeature.State(serverURL: state.root.serverURL, directoryPath: item.id, title: item.name))
                return .none

            case let .path(.element(id: _, action: .delegate(.openPath(path, title)))):
                return .send(.navigateToDirectory(path: path, title: title))

            case let .navigateToDirectory(path, title):
                state.path.removeAll()
                guard !path.isEmpty else { return .none }
                state.path.append(BrowseFeature.State(serverURL: state.root.serverURL, directoryPath: path, title: title))
                return .none

            case .root, .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            BrowseFeature()
        }
    }
}
