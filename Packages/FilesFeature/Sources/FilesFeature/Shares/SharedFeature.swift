import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import FolderPickerFeature
import Foundation
import Localization
import SwiftUI

/// The "Shared" tab: a segmented view over share links the user created ("By me") and
/// links others granted them ("With me"). Backed by `GET /api/shares` and
/// its shared with me variant. Deleting is owner only, so
/// it's offered on a "By me" share page only.
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
    /// reloads without a manual pull to refresh.
    public static let revisionKey = "shareLinksRevision"

    public enum EditPopover: Equatable, Sendable {
        case limit
        case expiry
        case renew
        case password
        case label
        case inline
    }

    @ObservableState
    public struct State: Equatable {
        public var serverURL: URL
        /// The account scope the saved lists are filed under, captured when this state was created.
        let cacheScope: String
        public var segment: Segment = .byMe
        public var byMe: IdentifiedArrayOf<Share> = []
        public var withMe: IdentifiedArrayOf<Share> = []
        /// Per segment load lifecycle. Each segment loads once on first view (`.loaded`);
        /// switching back doesn't rehit the server unless the user pulls to refresh or the
        /// last attempt `.failed`.
        public var phases: [Segment: DataPhase] = [:]
        /// Per segment: `.cached` while that segment shows an offline copy, `.live` once a fetch
        /// lands. Absent means `.live`.
        public var dataSources: [Segment: CachedListSource] = [:]
        /// A failed delete, or a refresh failure over an already populated segment, shown as a
        /// toast rather than the full screen `errorMessage`. Cleared once shown, so the same
        /// failure twice toasts twice.
        public var actionErrorMessage: String?
        /// A saved edit, confirmed with a toast once and then cleared like `actionErrorMessage`.
        public var actionSuccessMessage: String?
        public var deleteConfirmationShare: Share?
        public var deletingIDs: Set<Share.ID> = []
        /// The share being edited: a page pushed inside the detail sheet on iOS, a sheet on the Mac.
        @Presents public var editSheet: EditShareFeature.State?
        public var editPopover: EditPopover?
        /// The item sheet opened from a row; Edit and Delete stack on top of it.
        public var detail: Detail?
        public var searchQuery = ""
        /// The people row's pick per segment; absent means `.all`.
        public var filters: [Segment: Filter] = [:]
        public var sortOption: SortOption = .dateShared
        public var sortDirection: BrowseFeature.SortDirection = .descending
        /// `userId -> display name`, resolved from `GET /api/users/shareable` so a
        /// user specific share can name its recipients instead of just "Specific users".
        public var userNames: [String: String] = [:]
        public var userEmails: [String: String] = [:]
        public var shareFiles: [Share.ID: FileItem] = [:]
        public var requestedShareFileIDs: Set<Share.ID> = []
        /// Ticked on a timer (`expiryTick`) so a link that expires, or whose day countdown
        /// changes, while the tab is open updates on its own. Starts at `.distantPast`, so nothing
        /// reads as expired until the view's `TimelineView` sends the first real `now`, which
        /// it does immediately on appear. A non `Date()` default keeps `State()` deterministic.
        public var now: Date = .distantPast
        @Shared(.inMemory(SharedFeature.revisionKey)) public var externalRevision = 0

        public init(serverURL: URL) {
            self.serverURL = serverURL
            @Dependency(\.cacheScope) var cacheScopeSource
            cacheScope = cacheScopeSource.current()
        }

        /// The current segment's load state.
        public var phase: DataPhase {
            phase(for: segment)
        }

        public func phase(for segment: Segment) -> DataPhase {
            phases[segment] ?? .idle
        }

        /// The current segment's first load failure text, if that's still its state.
        public var errorMessage: String? {
            phase.errorMessage
        }

        func isExpired(_ share: Share) -> Bool {
            share.isExpired(now: now)
        }

        public func shares(for segment: Segment) -> IdentifiedArrayOf<Share> {
            segment == .byMe ? byMe : withMe
        }

        private func peopleNames(of share: Share) -> [String] {
            ([share.ownerId] + (share.permittedUserIds ?? [])).compactMap { userNames[$0] }
        }

        public var isSearching: Bool {
            !searchQuery.isEmpty
        }

        public var displayedShares: IdentifiedArrayOf<Share> {
            displayedShares(for: segment)
        }

        public func displayedShares(for segment: Segment) -> IdentifiedArrayOf<Share> {
            let term = SearchTerm(searchQuery)
            let base = isSearching
                ? shares(for: segment).filter { share in
                    term.matches(share.displayName)
                        || term.matches(share.sourcePath ?? "")
                        || peopleNames(of: share).contains { term.matches($0) }
                }
                : shares(for: segment)
            let sorted = base.sorted { lhs, rhs in
                switch sortOption {
                case .name:
                    lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                case .dateShared:
                    lhs.createdAt < rhs.createdAt
                case .expiration:
                    // No expiry sorts after any real date.
                    (lhs.expiresAt ?? .distantFuture) < (rhs.expiresAt ?? .distantFuture)
                }
            }
            return IdentifiedArray(
                sortDirection == .ascending ? sorted : sorted.reversed(),
                id: \.id,
                uniquingIDsWith: { first, _ in first }
            )
        }

        /// No shares in the current segment at all (before search): drives the empty state.
        public var isCurrentSegmentEmpty: Bool {
            isEmpty(for: segment)
        }

        public func isEmpty(for segment: Segment) -> Bool {
            shares(for: segment).isEmpty
        }

        /// A search that, with the people row's filter, left nothing to show.
        public func isSearchWithoutResults(for segment: Segment) -> Bool {
            isSearching && !shares(for: segment).isEmpty && items(for: segment).isEmpty
        }

        public func noResultsMessage(for segment: Segment) -> String {
            filters[segment] != nil && !displayedShares(for: segment).isEmpty
                ? L10n.Shared.noSearchMatchesFiltered(searchQuery)
                : L10n.Shared.noSearchMatches(searchQuery)
        }

        public func emptyMessage(for segment: Segment) -> String {
            segment == .byMe ? L10n.Shared.emptyByMe : L10n.Shared.emptyWithMe
        }

        /// Owner display name for a "With me" share: the recipient payload only carries
        /// `ownerId`, resolved against the shareable users list.
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
        case filterChanged(Segment, Filter)
        case refreshRequested
        case sortOptionChanged(SortOption)
        case sortDirectionChanged(BrowseFeature.SortDirection)
        case sharesResponse(Segment, Result<[Share], FilesClientError>)
        /// A segment's saved list read off the main actor after an offline failure, `nil` when none is stored.
        case offlineSharesResolved(Segment, cached: [Share]?, fetchedAt: Date?, error: FilesClientError)
        /// A segment's saved list read off the main actor to paint a first load.
        case cachedSharesPainted(Segment, [Share])
        case usersResponse([User])
        case shareFileNeeded(Share)
        case shareFileResponse(Share.ID, FileMetadata)
        case deleteTapped(Share)
        case deleteConfirmed
        case deleteCancelled
        case deleteResponse(Share.ID, Result<Bool, FilesClientError>)
        case editTapped(Share)
        case editPopoverTapped(Share, EditPopover)
        case editPopoverDismissed
        case labelEditEnded
        case accessModeChosen(Share, ShareAccessMode)
        case editSheet(PresentationAction<EditShareFeature.Action>)
        case actionToastShown
        case detailOpened(Segment, Item.ID)
        case detailDismissed
        case detailShareSelected(Share.ID?)
        case openTapped(Share)
        case downloadTapped(Share)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case openFolder(path: String, title: String)
            case downloadRequested([FileItem])
        }
    }

    @Dependency(\.filesClient) var filesClient
    @Dependency(\.jsonCacheStore) var jsonCacheStore
    @Dependency(\.date) var date

    static func cacheNamespace(_ segment: Segment) -> String {
        "shares.\(segment.rawValue)"
    }

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
                // Advancing `now` redraws the whole list. Only do it when a share crosses its
                // expiry or a day of its countdown in this interval, so a quiet list stays still.
                // The first tick always lands: it arrives before the first load, and shares that
                // load already expired must read as expired then, not on the next tick.
                let previousNow = state.now
                let crossesExpiry: (Share) -> Bool = { share in
                    guard let expiresAt = share.expiresAt else { return false }
                    return Self.expiryBoundaries(of: expiresAt).contains { $0 > previousNow && $0 <= now }
                }
                guard previousNow == .distantPast
                    || state.byMe.contains(where: crossesExpiry)
                    || state.withMe.contains(where: crossesExpiry)
                else {
                    return .none
                }
                state.now = now
                return .none

            case .externalRevisionChanged:
                state.phases.removeAll()
                return load(&state, segment: state.segment)

            case let .segmentChanged(segment):
                state.segment = segment
                switch state.phase(for: segment) {
                case .loading: return .none
                case .loaded: return fetch(state, segment: segment)
                case .idle, .failed: return load(&state, segment: segment)
                }

            case let .searchQueryChanged(query):
                state.searchQuery = query
                return .none

            case let .filterChanged(segment, tapped):
                let filter = state.filter(afterTapping: tapped, in: segment)
                state.filters[segment] = filter == .all ? nil : filter
                return .none

            case .refreshRequested:
                state.phases.removeAll()
                state.requestedShareFileIDs.removeAll()
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
                if segment == .byMe {
                    state.byMe = identified
                } else {
                    state.withMe = identified
                }
                state.sharesChanged()
                syncCache(state, segment: segment)
                return .none

            case let .sharesResponse(segment, .failure(error)):
                // Offline with a saved copy of this segment: show it under a banner.
                guard error == .offline else { return failLoad(&state, segment: segment, error) }
                let jsonCacheStore = jsonCacheStore
                let serverURL = state.serverURL
                let cacheScope = state.cacheScope
                return .run { send in
                    let cached = ListCache.load(
                        jsonCacheStore,
                        Self.cacheNamespace(segment),
                        serverURL: serverURL,
                        scope: cacheScope,
                        as: [Share].self
                    )
                    await send(.offlineSharesResolved(
                        segment,
                        cached: cached?.value,
                        fetchedAt: cached?.fetchedAt,
                        error: error
                    ))
                }
                .cancellable(id: CancelID.load(segment))

            case let .offlineSharesResolved(segment, cached, fetchedAt, error):
                guard let cached, let fetchedAt else { return failLoad(&state, segment: segment, error) }
                let identified = IdentifiedArray(cached, id: \.id, uniquingIDsWith: { first, _ in first })
                if segment == .byMe {
                    state.byMe = identified
                } else {
                    state.withMe = identified
                }
                state.phases[segment] = .loaded
                state.dataSources[segment] = .cached(fetchedAt: fetchedAt)
                state.sharesChanged()
                return .none

            case let .cachedSharesPainted(segment, cached):
                let isEmpty = (segment == .byMe ? state.byMe : state.withMe).isEmpty
                guard state.phases[segment] == .loading, isEmpty else { return .none }
                let identified = IdentifiedArray(cached, id: \.id, uniquingIDsWith: { first, _ in first })
                if segment == .byMe {
                    state.byMe = identified
                } else {
                    state.withMe = identified
                }
                state.sharesChanged()
                return .none

            case let .usersResponse(users):
                state.userNames = Dictionary(
                    users.map { ($0.id, $0.displayLabel) },
                    uniquingKeysWith: { first, _ in first }
                )
                state.userEmails = Dictionary(
                    users.compactMap { user in user.email.map { (user.id, $0) } },
                    uniquingKeysWith: { first, _ in first }
                )
                state.sharesChanged()
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
                let filesClient = filesClient
                return .run { send in
                    try await send(.deleteResponse(share.id, apiResult {
                        try await filesClient.deleteShareLink(serverURL, share.id)
                        return true
                    }), animation: DSMotion.listDiff)
                }

            case let .deleteResponse(id, .success):
                state.deletingIDs.remove(id)
                state.byMe.remove(id: id)
                state.sharesChanged()
                syncCache(state, segment: .byMe)
                return .none

            case let .deleteResponse(id, .failure(error)):
                state.deletingIDs.remove(id)
                state.actionErrorMessage = error.userMessage
                return .none

            case let .shareFileNeeded(share):
                guard !state.requestedShareFileIDs.contains(share.id),
                      share.fileItem() != nil,
                      let path = share.browsePath
                else { return .none }
                state.requestedShareFileIDs.insert(share.id)
                let serverURL = state.serverURL
                let filesClient = filesClient
                return .run { send in
                    if let metadata = try? await filesClient.fetchMetadata(serverURL, path) {
                        await send(.shareFileResponse(share.id, metadata))
                    }
                }

            case let .shareFileResponse(id, metadata):
                guard let share = state.byMe[id: id] else { return .none }
                state.shareFiles[id] = share.fileItem(size: metadata.size, modified: metadata.dateModified)
                return .none

            case let .editTapped(share):
                state.editPopover = nil
                state.editSheet = EditShareFeature.State(serverURL: state.serverURL, share: share, now: date.now)
                return .none

            case let .editPopoverTapped(share, popover):
                var edit = EditShareFeature.State(serverURL: state.serverURL, share: share, now: date.now)
                if popover == .limit {
                    edit.target = .users
                }
                state.editPopover = popover
                state.editSheet = edit
                return .none

            case let .accessModeChosen(share, mode):
                guard share.accessMode != mode, state.editPopover != .inline else { return .none }
                var edit = EditShareFeature.State(serverURL: state.serverURL, share: share, now: date.now)
                edit.accessMode = mode
                state.editPopover = .inline
                state.editSheet = edit
                return .send(.editSheet(.presented(.saveTapped)))

            case let .editSheet(.presented(.saveResponse(.failure(error))))
                where state.editPopover == .inline || state.editPopover == .label:
                state.actionErrorMessage = error.userMessage
                return .send(.editPopoverDismissed)

            case .labelEditEnded:
                guard state.editPopover == .label, let edit = state.editSheet else { return .none }
                if edit.hasChanges, !edit.trimmedLabel.isEmpty {
                    return .send(.editSheet(.presented(.saveTapped)))
                }
                return .send(.editPopoverDismissed)

            case .editPopoverDismissed:
                state.editPopover = nil
                state.editSheet = nil
                return .none

            case let .editSheet(.presented(.delegate(.updated(share)))):
                state.byMe[id: share.id] = share
                state.editSheet = nil
                state.editPopover = nil
                state.actionSuccessMessage = L10n.EditShare.saved
                state.sharesChanged()
                return .none

            case .editSheet:
                return .none

            case .actionToastShown:
                state.actionErrorMessage = nil
                state.actionSuccessMessage = nil
                return .none

            case let .detailOpened(segment, id):
                state.detail = Detail(segment: segment, id: id)
                return .none

            case .detailDismissed:
                state.detail = nil
                state.editSheet = nil
                return .none

            case let .detailShareSelected(id):
                if id != state.detail?.pushedShareID {
                    state.editSheet = nil
                }
                state.detail?.pushedShareID = id
                return .none

            case let .openTapped(share):
                guard share.isDirectory, state.withMe[id: share.id] != nil, !state.isExpired(share) else {
                    return .none
                }
                return .send(.delegate(.openFolder(path: share.receivedPath, title: share.itemName)))

            case let .downloadTapped(share):
                guard state.withMe[id: share.id] != nil, !state.isExpired(share), share.isDownloadAllowed,
                      let item = share.receivedFileItem
                else { return .none }
                return .send(.delegate(.downloadRequested([item])))

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$editSheet, action: \.editSheet) {
            EditShareFeature()
        }
    }

    /// Full screen error only when that segment has nothing to blank; a refresh failure over a
    /// populated segment stays `.loaded` and toasts.
    private func failLoad(_ state: inout State, segment: Segment, _ error: FilesClientError) -> Effect<Action> {
        let segmentEmpty = (segment == .byMe ? state.byMe : state.withMe).isEmpty
        if segmentEmpty {
            state.phases[segment] = .failed(error.userMessage)
        } else {
            state.phases[segment] = .loaded
            state.actionErrorMessage = error.userMessage
        }
        return .none
    }

    private func load(_ state: inout State, segment: Segment) -> Effect<Action> {
        // Paint the saved copy on a first load (stale while revalidate); a successful fetch replaces
        // it, only a failed one surfaces the offline banner. The disk read runs beside the fetch, off
        // the main actor, and is dropped if the fetch won.
        let current = segment == .byMe ? state.byMe : state.withMe
        let paint: Effect<Action>
        if !(state.phases[segment]?.hasLoaded ?? false), current.isEmpty {
            let jsonCacheStore = jsonCacheStore
            let serverURL = state.serverURL
            let cacheScope = state.cacheScope
            paint = .run { send in
                guard let cached = ListCache.load(
                    jsonCacheStore,
                    Self.cacheNamespace(segment),
                    serverURL: serverURL,
                    scope: cacheScope,
                    as: [Share].self
                ) else { return }
                await send(.cachedSharesPainted(segment, cached.value))
            }
        } else {
            paint = .none
        }
        state.phases[segment] = .loading
        return .merge(paint, fetch(state, segment: segment))
    }

    private func fetch(_ state: State, segment: Segment) -> Effect<Action> {
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            try await send(.sharesResponse(segment, apiResult {
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
        ListCache.save(
            jsonCacheStore,
            Self.cacheNamespace(segment),
            serverURL: state.serverURL,
            scope: state.cacheScope,
            value: Array(shares)
        )
    }

    /// Best effort: recipient names are a nicety, not worth surfacing an error for.
    private func loadUsers(_ state: State) -> Effect<Action> {
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            if let users = try? await filesClient.shareableUsers(serverURL) {
                await send(.usersResponse(users))
            }
        }
    }
}
