import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

/// The "Shared" tab: a segmented view over share links the user created ("By me") and
/// links others granted them ("With me"). Backed by `GET /api/shares` and
/// `GET /api/shares/shared-with-me` — see [[share-link-api]]. Deleting is owner-only, so
/// it's offered on the "By me" list only.
@Reducer
public struct SharedFeature {
    public enum Segment: String, Hashable, Sendable, CaseIterable {
        case byMe
        case withMe

        var title: String {
            switch self {
            case .byMe: "By me"
            case .withMe: "With me"
            }
        }
    }

    @ObservableState
    public struct State: Equatable {
        public var serverURL: URL
        public var segment: Segment = .byMe
        public var byMe: IdentifiedArrayOf<Share> = []
        public var withMe: IdentifiedArrayOf<Share> = []
        public var isLoading = false
        public var errorMessage: String?
        /// Each segment loads once on first view; switching back doesn't re-hit the server
        /// unless the user pulls to refresh.
        public var loadedSegments: Set<Segment> = []
        public var deleteConfirmationShare: Share?
        public var deletingIDs: Set<Share.ID> = []

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        public var displayedShares: IdentifiedArrayOf<Share> {
            segment == .byMe ? byMe : withMe
        }

        public var isCurrentSegmentEmpty: Bool {
            displayedShares.isEmpty
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case segmentChanged(Segment)
        case refreshRequested
        case sharesResponse(Segment, Result<[Share], FilesClientError>)
        case deleteTapped(Share)
        case deleteConfirmed
        case deleteCancelled
        case deleteResponse(Share.ID, Result<Bool, FilesClientError>)
    }

    @Dependency(\.filesClient) var filesClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard !state.loadedSegments.contains(state.segment) else { return .none }
                return load(&state, segment: state.segment)

            case let .segmentChanged(segment):
                state.segment = segment
                state.errorMessage = nil
                guard !state.loadedSegments.contains(segment) else { return .none }
                return load(&state, segment: segment)

            case .refreshRequested:
                return load(&state, segment: state.segment)

            case let .sharesResponse(segment, .success(shares)):
                state.isLoading = false
                state.errorMessage = nil
                state.loadedSegments.insert(segment)
                let identified = IdentifiedArray(uniqueElements: shares)
                if segment == .byMe { state.byMe = identified } else { state.withMe = identified }
                return .none

            case let .sharesResponse(_, .failure(error)):
                state.isLoading = false
                state.errorMessage = error.userMessage
                return .none

            case let .deleteTapped(share):
                state.deleteConfirmationShare = share
                return .none

            case .deleteCancelled:
                state.deleteConfirmationShare = nil
                return .none

            case .deleteConfirmed:
                guard let share = state.deleteConfirmationShare else { return .none }
                state.deleteConfirmationShare = nil
                state.deletingIDs.insert(share.id)
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    do {
                        try await filesClient.deleteShareLink(serverURL, share.id)
                        await send(.deleteResponse(share.id, .success(true)), animation: .default)
                    } catch {
                        await send(.deleteResponse(share.id, .failure((error as? FilesClientError) ?? .network(String(describing: error)))))
                    }
                }

            case let .deleteResponse(id, .success):
                state.deletingIDs.remove(id)
                state.byMe.remove(id: id)
                return .none

            case let .deleteResponse(id, .failure(error)):
                state.deletingIDs.remove(id)
                state.errorMessage = error.userMessage
                return .none
            }
        }
    }

    private func load(_ state: inout State, segment: Segment) -> Effect<Action> {
        state.isLoading = true
        state.errorMessage = nil
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        return .run { send in
            do {
                let shares = try segment == .byMe
                    ? await filesClient.mySharedLinks(serverURL)
                    : await filesClient.sharedWithMeLinks(serverURL)
                await send(.sharesResponse(segment, .success(shares)))
            } catch {
                await send(.sharesResponse(segment, .failure((error as? FilesClientError) ?? .network(String(describing: error)))))
            }
        }
    }
}
