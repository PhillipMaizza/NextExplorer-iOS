import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Foundation
import SwiftUI

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

    public enum SortOption: String, Hashable, Sendable, CaseIterable {
        case dateShared
        case name
        case expiration

        var title: String {
            switch self {
            case .dateShared: "Date Shared"
            case .name: "Name"
            case .expiration: "Expiration"
            }
        }

        var icon: Image {
            switch self {
            case .dateShared: IconKit.calendar
            case .name: IconKit.textformat
            case .expiration: IconKit.time
            }
        }
    }

    /// Bumped by `CreateShareLinkFeature` whenever a link is created, so the Shared tab
    /// reloads without a manual pull-to-refresh.
    public static let revisionKey = "shareLinksRevision"

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
        public var sortOption: SortOption = .dateShared
        public var sortDirection: BrowseFeature.SortDirection = .descending
        /// `userId -> display name`, resolved from `GET /api/users/shareable` so a
        /// user-specific share can name its recipients instead of just "Specific users".
        public var userNames: [String: String] = [:]
        @Shared(.inMemory(SharedFeature.revisionKey)) public var externalRevision = 0

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        public var displayedShares: IdentifiedArrayOf<Share> {
            let base = segment == .byMe ? byMe : withMe
            let sorted = base.sorted { lhs, rhs in
                switch sortOption {
                case .name:
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                case .dateShared:
                    return lhs.createdAt < rhs.createdAt
                case .expiration:
                    // No expiry sorts after any real date.
                    return (lhs.expiresAt ?? .distantFuture) < (rhs.expiresAt ?? .distantFuture)
                }
            }
            return IdentifiedArray(uniqueElements: sortDirection == .ascending ? sorted : sorted.reversed())
        }

        public var activeShares: IdentifiedArrayOf<Share> {
            IdentifiedArray(uniqueElements: displayedShares.filter { !$0.isExpired })
        }

        public var expiredShares: IdentifiedArrayOf<Share> {
            IdentifiedArray(uniqueElements: displayedShares.filter(\.isExpired))
        }

        public var isCurrentSegmentEmpty: Bool {
            displayedShares.isEmpty
        }

        /// What to print in a share's "Shared with" row.
        public func sharedWithLabel(for share: Share) -> String {
            guard share.sharingType == .users else { return "Anyone with link" }
            let ids = share.permittedUserIds ?? []
            let names = ids.compactMap { userNames[$0] }
            if names.isEmpty {
                return ids.isEmpty ? "Specific people" : "\(ids.count) \(ids.count == 1 ? "person" : "people")"
            }
            if names.count <= 2 { return names.joined(separator: ", ") }
            return "\(names[0]), \(names[1]) +\(names.count - 2)"
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case externalRevisionChanged
        case segmentChanged(Segment)
        case refreshRequested
        case sortOptionChanged(SortOption)
        case sortDirectionChanged(BrowseFeature.SortDirection)
        case sharesResponse(Segment, Result<[Share], FilesClientError>)
        case usersResponse([User])
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
                return .merge(load(&state, segment: state.segment), loadUsers(state))

            case .externalRevisionChanged:
                state.loadedSegments = []
                return load(&state, segment: state.segment)

            case let .segmentChanged(segment):
                state.segment = segment
                state.errorMessage = nil
                guard !state.loadedSegments.contains(segment) else { return .none }
                return load(&state, segment: segment)

            case .refreshRequested:
                state.loadedSegments = []
                return .merge(load(&state, segment: state.segment), loadUsers(state))

            case let .sortOptionChanged(option):
                state.sortOption = option
                return .none

            case let .sortDirectionChanged(direction):
                state.sortDirection = direction
                return .none

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

            case let .usersResponse(users):
                state.userNames = Dictionary(
                    users.map { ($0.id, $0.displayName ?? $0.username) },
                    uniquingKeysWith: { first, _ in first }
                )
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

    /// Best-effort — recipient names are a nicety, not worth surfacing an error for.
    private func loadUsers(_ state: State) -> Effect<Action> {
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        return .run { send in
            if let users = try? await filesClient.shareableUsers(serverURL) {
                await send(.usersResponse(users))
            }
        }
    }
}
