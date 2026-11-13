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
        var removal: OfflineRemovalRequest?

        public init() {}

        public var totalBytes: Int64 {
            usages.reduce(Int64(0)) { $0 + $1.sizeBytes }
        }

        public var isEmpty: Bool {
            usages.isEmpty
        }

        /// Asks to remove the pinned items at `paths`; paths that are not listed are ignored.
        mutating func requestRemoval(of paths: [String]) {
            let listed = paths.compactMap { usages[id: $0] }
            guard !listed.isEmpty else { return }
            removal = OfflineRemovalRequest(
                paths: listed.map(\.root.path),
                names: listed.map { usage in
                    let name = (usage.root.path as NSString).lastPathComponent
                    return name.isEmpty ? usage.root.path : name
                }
            )
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case usagesLoaded([OfflinePinnedRootUsage])
        /// Asks first: removing deletes the copy on this device.
        case removeTapped(path: String)
        /// The Mac table removes several rows at once; one confirmation covers them all.
        case removeSelectionTapped(paths: [String])
        case removeConfirmed
        case removeCancelled
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
                state.requestRemoval(of: [path])
                return .none

            case let .removeSelectionTapped(paths):
                state.requestRemoval(of: paths)
                return .none

            case .removeCancelled:
                state.removal = nil
                return .none

            case .removeConfirmed:
                guard let request = state.removal else { return .none }
                state.removal = nil
                for path in request.paths {
                    state.usages.remove(id: path)
                }
                let paths = request.paths
                let offlineFileStore = offlineFileStore
                return .merge(
                    .run { _ in paths.forEach(offlineFileStore.removeRoot) },
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
