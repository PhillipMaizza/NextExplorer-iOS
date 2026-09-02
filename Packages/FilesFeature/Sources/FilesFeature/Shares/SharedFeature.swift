import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Foundation
import Localization
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
            case .byMe: L10n.Shared.segmentByMe
            case .withMe: L10n.Shared.segmentWithMe
            }
        }
    }

    public enum SortOption: String, Hashable, Sendable, CaseIterable {
        case dateShared
        case name
        case expiration

        var title: String {
            switch self {
            case .dateShared: L10n.Sort.dateShared
            case .name: L10n.Sort.name
            case .expiration: L10n.Sort.expiration
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
        /// Per segment load lifecycle. Each segment loads once on first view (`.loaded`);
        /// switching back doesn't re-hit the server unless the user pulls to refresh or the
        /// last attempt `.failed`.
        public var phases: [Segment: DataPhase] = [:]
        /// Per segment: `.cached` while that segment shows an offline copy, `.live` once a fetch
        /// lands. Absent means `.live`.
        public var dataSources: [Segment: CachedListSource] = [:]
        /// A failed delete, or a refresh failure over an already populated segment, shown as a
        /// toast rather than the full screen `errorMessage`.
        public var actionErrorMessage: String?
        public var deleteConfirmationShare: Share?
        public var deletingIDs: Set<Share.ID> = []
        @Presents public var editSheet: EditShareFeature.State?
        public var searchQuery = ""
        public var sortOption: SortOption = .dateShared
        public var sortDirection: BrowseFeature.SortDirection = .descending
        /// `userId -> display name`, resolved from `GET /api/users/shareable` so a
        /// user-specific share can name its recipients instead of just "Specific users".
        public var userNames: [String: String] = [:]
        /// Ticked on a timer (`expiryTick`) so a link that expires while the tab is open
        /// slides into the "Expired" section on its own. Starts at `.distantPast`, so nothing
        /// reads as expired until the view's `TimelineView` sends the first real `now`, which
        /// it does immediately on appear. A non `Date()` default keeps `State()` deterministic.
        public var now: Date = .distantPast
        @Shared(.inMemory(SharedFeature.revisionKey)) public var externalRevision = 0

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        /// The current segment's load state.
        public var phase: DataPhase { phase(for: segment) }

        public func phase(for segment: Segment) -> DataPhase { phases[segment] ?? .idle }

        /// The current segment's first load failure text, if that's still its state.
        public var errorMessage: String? { phase.errorMessage }

        func isExpired(_ share: Share) -> Bool {
            guard let expiresAt = share.expiresAt else { return false }
            return expiresAt <= now
        }

        /// The current segment's raw (unfiltered, unsorted) list.
        public var segmentShares: IdentifiedArrayOf<Share> { shares(for: segment) }

        public func shares(for segment: Segment) -> IdentifiedArrayOf<Share> {
            segment == .byMe ? byMe : withMe
        }

        public var isSearching: Bool { !searchQuery.isEmpty }

        public var displayedShares: IdentifiedArrayOf<Share> { displayedShares(for: segment) }

        public func displayedShares(for segment: Segment) -> IdentifiedArrayOf<Share> {
            let base = isSearching
                ? shares(for: segment).filter {
                    FuzzyMatch.matches(query: searchQuery, in: $0.displayName)
                        || FuzzyMatch.matches(query: searchQuery, in: $0.sourcePath ?? "")
                }
                : shares(for: segment)
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
            return IdentifiedArray(sortDirection == .ascending ? sorted : sorted.reversed(), id: \.id, uniquingIDsWith: { first, _ in first })
        }

        public var activeShares: IdentifiedArrayOf<Share> { activeShares(for: segment) }

        public func activeShares(for segment: Segment) -> IdentifiedArrayOf<Share> {
            displayedSharesPartition(for: segment).active
        }

        public var expiredShares: IdentifiedArrayOf<Share> { expiredShares(for: segment) }

        public func expiredShares(for segment: Segment) -> IdentifiedArrayOf<Share> {
            displayedSharesPartition(for: segment).expired
        }

        /// One filter+sort pass, split into active/expired. `activeShares`, `expiredShares` and
        /// the list's `.animation(value:)` all need slices of the same ordered list; deriving
        /// each independently ran the localized sort three times per render.
        public func displayedSharesPartition(
            for segment: Segment
        ) -> (all: IdentifiedArrayOf<Share>, active: IdentifiedArrayOf<Share>, expired: IdentifiedArrayOf<Share>) {
            let all = displayedShares(for: segment)
            let active = IdentifiedArray(all.filter { !isExpired($0) }, id: \.id, uniquingIDsWith: { first, _ in first })
            let expired = IdentifiedArray(all.filter(isExpired), id: \.id, uniquingIDsWith: { first, _ in first })
            return (all, active, expired)
        }

        /// No shares in the current segment at all (before search) — drives the empty state.
        public var isCurrentSegmentEmpty: Bool { isEmpty(for: segment) }

        public func isEmpty(for segment: Segment) -> Bool { shares(for: segment).isEmpty }

        /// A search that filtered everything out.
        public var isSearchWithoutResults: Bool { isSearchWithoutResults(for: segment) }

        public func isSearchWithoutResults(for segment: Segment) -> Bool {
            isSearching && !shares(for: segment).isEmpty && displayedShares(for: segment).isEmpty
        }

        public func emptyMessage(for segment: Segment) -> String {
            segment == .byMe ? L10n.Shared.emptyByMe : L10n.Shared.emptyWithMe
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
            userNames[share.ownerId] ?? L10n.Shared.sharedByUnknown
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
        case editTapped(Share)
        case editSheet(PresentationAction<EditShareFeature.Action>)
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.jsonCacheStore) var jsonCacheStore

    private static func cacheNamespace(_ segment: Segment) -> String { "shares.\(segment.rawValue)" }

    /// Per segment, so a spammed pull to refresh (or a fast segment reselect) supersedes the
    /// previous same segment load instead of racing it, while the other segment keeps loading.
    private enum CancelID: Hashable { case load(Segment) }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.phase.shouldLoadOnAppear else { return .none }
                return .concatenate(load(&state, segment: state.segment), loadUsers(state))

            case let .expiryTick(now):
                // Advancing `now` re-renders the whole list. Only do it when a share actually
                // crosses its expiry in this interval, so a quiet list stays still between ticks.
                let previousNow = state.now
                let crossesExpiry: (Share) -> Bool = { share in
                    guard let expiresAt = share.expiresAt else { return false }
                    return expiresAt > previousNow && expiresAt <= now
                }
                guard state.byMe.contains(where: crossesExpiry) || state.withMe.contains(where: crossesExpiry) else {
                    return .none
                }
                state.now = now
                return .none

            case .externalRevisionChanged:
                state.phases.removeAll()
                return load(&state, segment: state.segment)

            case let .segmentChanged(segment):
                state.segment = segment
                guard (state.phases[segment] ?? .idle).shouldLoadOnAppear else { return .none }
                return load(&state, segment: segment)

            case let .searchQueryChanged(query):
                state.searchQuery = query
                return .none

            case .refreshRequested:
                state.phases.removeAll()
                return .concatenate(load(&state, segment: state.segment), loadUsers(state))

            case let .sortOptionChanged(option):
                state.sortOption = option
                return .none

            case let .sortDirectionChanged(direction):
                state.sortDirection = direction
                return .none

            case let .sharesResponse(segment, .success(shares)):
                state.phases[segment] = .loaded
                state.dataSources[segment] = .live
                let identified = IdentifiedArray(shares, id: \.id, uniquingIDsWith: { first, _ in first })
                if segment == .byMe { state.byMe = identified } else { state.withMe = identified }
                syncCache(state, segment: segment)
                return .none

            case let .sharesResponse(segment, .failure(error)):
                // Offline with a saved copy of this segment: show it under a banner.
                if error == .offline,
                   let cached = ListCache.load(jsonCacheStore, Self.cacheNamespace(segment), serverURL: state.serverURL, as: [Share].self) {
                    let identified = IdentifiedArray(cached.value, id: \.id, uniquingIDsWith: { first, _ in first })
                    if segment == .byMe { state.byMe = identified } else { state.withMe = identified }
                    state.phases[segment] = .loaded
                    state.dataSources[segment] = .cached(fetchedAt: cached.fetchedAt)
                    return .none
                }
                // Full screen error only when that segment has nothing to blank; a refresh
                // failure over a populated segment stays `.loaded` and toasts.
                let segmentEmpty = (segment == .byMe ? state.byMe : state.withMe).isEmpty
                if segmentEmpty {
                    state.phases[segment] = .failed(error.userMessage)
                } else {
                    state.phases[segment] = .loaded
                    state.actionErrorMessage = error.userMessage
                }
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
                    await send(.deleteResponse(share.id, try await apiResult {
                        try await filesClient.deleteShareLink(serverURL, share.id)
                        return true
                    }), animation: .default)
                }

            case let .deleteResponse(id, .success):
                state.deletingIDs.remove(id)
                state.byMe.remove(id: id)
                syncCache(state, segment: .byMe)
                return .none

            case let .deleteResponse(id, .failure(error)):
                state.deletingIDs.remove(id)
                state.actionErrorMessage = error.userMessage
                return .none

            case let .editTapped(share):
                state.editSheet = EditShareFeature.State(serverURL: state.serverURL, share: share)
                return .none

            case let .editSheet(.presented(.delegate(.updated(share)))):
                state.byMe[id: share.id] = share
                state.editSheet = nil
                return .none

            case .editSheet:
                return .none
            }
        }
        .ifLet(\.$editSheet, action: \.editSheet) {
            EditShareFeature()
        }
    }

    private func load(_ state: inout State, segment: Segment) -> Effect<Action> {
        // Paint the saved copy immediately on a first load (stale-while-revalidate); a
        // successful fetch replaces it, only a failed one surfaces the offline banner.
        let current = segment == .byMe ? state.byMe : state.withMe
        if !(state.phases[segment]?.hasLoaded ?? false), current.isEmpty,
           let cached = ListCache.load(jsonCacheStore, Self.cacheNamespace(segment), serverURL: state.serverURL, as: [Share].self) {
            let identified = IdentifiedArray(cached.value, id: \.id, uniquingIDsWith: { first, _ in first })
            if segment == .byMe { state.byMe = identified } else { state.withMe = identified }
        }
        state.phases[segment] = .loading
        let serverURL = state.serverURL
        let filesClient = self.filesClient
        return .run { send in
            await send(.sharesResponse(segment, try await apiResult {
                try segment == .byMe
                    ? await filesClient.mySharedLinks(serverURL)
                    : await filesClient.sharedWithMeLinks(serverURL)
            }))
        }
        .cancellable(id: CancelID.load(segment), cancelInFlight: true)
    }

    /// Persists a segment's current list as its offline copy.
    private func syncCache(_ state: State, segment: Segment) {
        let shares = segment == .byMe ? state.byMe : state.withMe
        ListCache.save(jsonCacheStore, Self.cacheNamespace(segment), serverURL: state.serverURL, value: Array(shares))
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
