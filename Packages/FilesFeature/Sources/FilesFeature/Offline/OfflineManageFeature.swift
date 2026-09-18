import ComposableArchitecture
import FilesClient
import Foundation

/// Lists what the user has pinned for offline use, with each pinned root's size, and lets them remove
/// any one of them. Reads and mutates the offline store directly (no network); a removal emits a
/// delegate so Settings can refresh its offline size.
@Reducer
public struct OfflineManageFeature {
    @ObservableState
    public struct State: Equatable {
        public var usages: IdentifiedArrayOf<OfflinePinnedRootUsage> = []

        public init() {}

        public var totalBytes: Int64 {
            usages.reduce(Int64(0)) { $0 + $1.sizeBytes }
        }

        public var isEmpty: Bool {
            usages.isEmpty
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case usagesLoaded([OfflinePinnedRootUsage])
        case removeTapped(path: String)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            /// The pinned set changed; Settings should re-read its offline size.
            case changed
        }
    }

    @Dependency(\.offlineFileStore) var offlineFileStore

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return load()

            case let .usagesLoaded(usages):
                state.usages = IdentifiedArray(uniqueElements: usages)
                return .none

            case let .removeTapped(path):
                state.usages.remove(id: path)
                let offlineFileStore = offlineFileStore
                return .merge(
                    .run { _ in offlineFileStore.removeRoot(path) },
                    .send(.delegate(.changed))
                )

            case .delegate:
                return .none
            }
        }
    }

    private func load() -> Effect<Action> {
        let offlineFileStore = offlineFileStore
        return .run { send in
            // Sizing walks the slot directory, so keep it off the main actor.
            let usages = await Task.detached(priority: .utility) { offlineFileStore.pinnedRootUsages() }.value
            await send(.usagesLoaded(usages))
        }
    }
}
