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
        /// A failed delete — shown as a toast, not the list-level `errorMessage`.
        public var actionErrorMessage: String?
        /// Each segment loads once on first view; switching back doesn't re-hit the server
        /// unless the user pulls to refresh.
        public var loadedSegments: Set<Segment> = []
        public var deleteConfirmationShare: Share?
        public var deletingIDs: Set<Share.ID> = []
        public var searchQuery = ""
        public var sortOption: SortOption = .dateShared
        public var sortDirection: BrowseFeature.SortDirection = .descending
        /// `userId -> display name`, resolved from `GET /api/users/shareable` so a
        /// user-specific share can name its recipients instead of just "Specific users".
        public var userNames: [String: String] = [:]
        /// Ticked on a timer (`expiryTick`) so a link that expires while the tab is open
        /// slides into the "Expired" section on its own. Starts at `.distantPast` — nothing
        /// reads as expired until the view's `TimelineView` sends the first real `now`, which
        /// it does immediately on appear. A non-`Date()` default keeps `State()` deterministic.
        public var now: Date = .distantPast
        @Shared(.inMemory(SharedFeature.revisionKey)) public var externalRevision = 0

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        func isExpired(_ share: Share) -> Bool {
            guard let expiresAt = share.expiresAt else { return false }
            return expiresAt <= now
        }

        /// The current segment's raw (unfiltered, unsorted) list.
        public var segmentShares: IdentifiedArrayOf<Share> {
            segment == .byMe ? byMe : withMe
        }

        public var isSearching: Bool { !searchQuery.isEmpty }

        public var displayedShares: IdentifiedArrayOf<Share> {
            let base = isSearching
                ? segmentShares.filter {
                    FuzzyMatch.matches(query: searchQuery, in: $0.displayName)
                        || FuzzyMatch.matches(query: searchQuery, in: $0.sourcePath ?? "")
                }
                : segmentShares
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
            IdentifiedArray(uniqueElements: displayedShares.filter { !isExpired($0) })
        }

        public var expiredShares: IdentifiedArrayOf<Share> {
            IdentifiedArray(uniqueElements: displayedShares.filter(isExpired))
        }

        /// No shares in this segment at all (before search) — drives the empty state.
        public var isCurrentSegmentEmpty: Bool {
            segmentShares.isEmpty
        }

        /// A search that filtered everything out.
        public var isSearchWithoutResults: Bool {
            isSearching && !segmentShares.isEmpty && displayedShares.isEmpty
        }

        /// How a share's audience renders in the "Shared with" row.
        public enum Audience: Equatable, Sendable {
            case anyone
            /// Resolved recipient names plus a count of any that couldn't be named yet.
            case users(names: [String], unnamed: Int)
        }

        public func audience(for share: Share) -> Audience {
            guard share.sharingType == .users else { return .anyone }
            let ids = share.permittedUserIds ?? []
            let names = ids.compactMap { userNames[$0] }
            return .users(names: names, unnamed: ids.count - names.count)
        }

        /// Owner display name for a "With me" share — the recipient payload only carries
        /// `ownerId`, resolved against the shareable-users list.
        public func sharedByLabel(for share: Share) -> String {
            userNames[share.ownerId] ?? "Someone"
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case expiryTick(Date)
        case externalRevisionChanged
        case segmentChanged(Segment)
        case searchQueryChanged(String)
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
                return .concatenate(load(&state, segment: state.segment), loadUsers(state))

            case let .expiryTick(now):
                state.now = now
                return .none

            case .externalRevisionChanged:
                state.loadedSegments = []
                return load(&state, segment: state.segment)

            case let .segmentChanged(segment):
                state.segment = segment
                state.errorMessage = nil
                guard !state.loadedSegments.contains(segment) else { return .none }
                return load(&state, segment: segment)

            case let .searchQueryChanged(query):
                state.searchQuery = query
                return .none

            case .refreshRequested:
                state.loadedSegments = []
                return .concatenate(load(&state, segment: state.segment), loadUsers(state))

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
                    await send(.deleteResponse(share.id, await apiResult {
                        try await filesClient.deleteShareLink(serverURL, share.id)
                        return true
                    }), animation: .default)
                }

            case let .deleteResponse(id, .success):
                state.deletingIDs.remove(id)
                state.byMe.remove(id: id)
                return .none

            case let .deleteResponse(id, .failure(error)):
                state.deletingIDs.remove(id)
                state.actionErrorMessage = error.userMessage
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
            await send(.sharesResponse(segment, await apiResult {
                try segment == .byMe
                    ? await filesClient.mySharedLinks(serverURL)
                    : await filesClient.sharedWithMeLinks(serverURL)
            }))
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
