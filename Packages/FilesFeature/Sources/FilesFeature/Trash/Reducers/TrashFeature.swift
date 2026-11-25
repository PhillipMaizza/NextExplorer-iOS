import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import FolderPickerFeature
import Foundation
import Localization

/// The person's trash: what they deleted (an administrator sees everyone's), restore in place or
/// into a folder, look inside a deleted folder or read a text file, and delete for good. Never
/// cached: the server forbids storing these answers, and nothing of it outlives the screen.
@Reducer
public struct TrashFeature {
    @ObservableState
    public struct State: Equatable {
        public var serverURL: URL
        public var phase: DataPhase = .idle
        public var items: IdentifiedArrayOf<TrashItem> = []
        public var isEnabled = true
        public var retentionDays: Int?
        public var isSelecting = false
        public var selectedIDs: Set<TrashItem.ID> = []
        /// Newest deletions first until the user picks another order; kept for the screen's life.
        public var sortOption: TrashSortOption = .deletedOn
        public var sortDirection: BrowseFeature.SortDirection = .descending
        /// A delete for good or Empty Trash waiting for its confirmation, then running.
        public var confirmation: Confirmation?
        public var confirmPhase: ConfirmPhase = .idle
        public var restore: TrashRestoreFeature.State
        @Presents public var folder: TrashFolderFeature.State?
        public var text: TrashTextPreview.State = .closed
        public var notice: TrashNotice?
        public var searchQuery = ""

        public init(serverURL: URL) {
            self.serverURL = serverURL
            restore = TrashRestoreFeature.State(serverURL: serverURL)
        }

        public var isBusy: Bool {
            confirmPhase.isRunning || restore.isRestoring
        }

        public var selectedItems: [TrashItem] {
            items.filter { selectedIDs.contains($0.id) }
        }

        /// The items in the order the list shows them.
        public var displayedItems: [TrashItem] {
            let term = searchQuery.trimmingCharacters(in: .whitespaces)
            let matches = term.isEmpty
                ? items.elements
                : items.elements.filter { $0.name.localizedStandardContains(term) }
            return matches.sorted(by: sortOption, sortDirection)
        }

        public var searchMiss: String? {
            searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || !displayedItems.isEmpty
                ? nil
                : L10n.EmptyState.noSearchMatches(searchQuery)
        }

        public var isAllSelected: Bool {
            let shown = displayedItems
            return !shown.isEmpty && selectedIDs.count == shown.count
        }
    }

    public enum Confirmation: Equatable, Sendable {
        /// `forget`: an administrator dropping the records of items whose volume is gone.
        case purge(ids: [TrashItem.ID], forget: Bool)
        case empty
    }

    public enum Action: Equatable, Sendable {
        case task
        case refreshPulled
        case retryTapped
        case loadResponse(Result<TrashListing, FilesClientError>)
        case itemTapped(TrashItem)
        case selectModeToggled
        case selectionToggled(TrashItem.ID)
        case selectAllTapped
        case selectionSwept(Set<TrashItem.ID>)
        case sortOptionChanged(TrashSortOption)
        case sortDirectionChanged(BrowseFeature.SortDirection)
        case searchQueryChanged(String)
        case restoreTapped([TrashItem])
        case restoreToTapped([TrashItem])
        case deletePermanentlyTapped([TrashItem])
        case forgetTapped(TrashItem)
        case emptyTrashTapped
        case confirmationConfirmed
        case confirmationDismissed
        case purgeResponse(Result<TrashActionResult, FilesClientError>)
        case emptyResponse(Result<TrashEmptySummary, FilesClientError>)
        case openLocationTapped(TrashItem)
        case textDismissed
        case textResponse(Result<TrashText, FilesClientError>)
        case restore(TrashRestoreFeature.Action)
        case folder(PresentationAction<TrashFolderFeature.Action>)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            /// Open Original Location: the folder an item was deleted from.
            case openPath(path: String, title: String)
            /// Items went back into folders: listings on screen read them again.
            case restored
        }
    }

    enum CancelID {
        case load, mutation, text
    }

    @Dependency(\.filesClient) var filesClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.restore, action: \.restore) {
            TrashRestoreFeature()
        }
        Reduce { state, action in
            switch action {
            case .task:
                guard state.phase.shouldLoadOnAppear else { return .none }
                return load(&state)

            case .refreshPulled, .retryTapped:
                return load(&state)

            case .restore(.delegate(.finished)):
                state.isSelecting = false
                state.selectedIDs = []
                return .merge(load(&state), .send(.delegate(.restored)))

            case let .folder(.presented(.delegate(.restored(isWholeFolder)))):
                if isWholeFolder {
                    // The folder's screen closes, and its toast with it: the list shows the result and its Undo.
                    if let finished = state.folder?.restore, let notice = finished.notice {
                        state.restore.undoable = finished.undoable
                        state.restore.notice = TrashNotice.after(
                            state.restore.notice,
                            text: notice.text,
                            isFailure: notice.isFailure,
                            isUndoable: notice.isUndoable
                        )
                    }
                    state.folder = nil
                }
                return .merge(load(&state), .send(.delegate(.restored)))

            case let .loadResponse(.success(listing)):
                state.phase = .loaded
                state.items = IdentifiedArray(listing.items, uniquingIDsWith: { first, _ in first })
                state.isEnabled = listing.isEnabled
                state.retentionDays = listing.retentionDays
                state.selectedIDs.formIntersection(state.items.ids)
                return .none

            case let .loadResponse(.failure(error)):
                // A reload over a list on screen keeps it and says why in a toast.
                if state.items.isEmpty {
                    state.phase = .failed(error == .offline ? error.userMessage : L10n.Trash.loadFailed)
                } else {
                    state.phase = .loaded
                    state.notice = TrashNotice.after(state.notice, text: error.userMessage, isFailure: true)
                }
                return .none

            case let .searchQueryChanged(query):
                state.searchQuery = query
                state.selectedIDs.formIntersection(state.displayedItems.map(\.id))
                return .none

            case let .itemTapped(item):
                if state.isSelecting {
                    return .send(.selectionToggled(item.id))
                }
                guard item.isAvailable else { return .none }
                if item.isDirectory {
                    state.folder = TrashFolderFeature.State(serverURL: state.serverURL, item: item)
                    return .none
                }
                guard TrashTextPreview.canOpen(name: item.name) else { return .none }
                return TrashTextPreview.open(
                    &state.text,
                    name: item.name,
                    itemID: item.id,
                    path: "",
                    serverURL: state.serverURL,
                    filesClient: filesClient
                )
                .map(Action.textResponse)
                .cancellable(id: CancelID.text, cancelInFlight: true)

            case let .textResponse(result):
                if let error = state.text.receive(result) {
                    state.notice = .after(state.notice, text: error.userMessage, isFailure: true)
                }
                return .none

            case .textDismissed:
                state.text = .closed
                return .cancel(id: CancelID.text)

            case .selectModeToggled:
                state.isSelecting.toggle()
                state.selectedIDs = []
                return .none

            case let .selectionToggled(id):
                if state.selectedIDs.contains(id) {
                    state.selectedIDs.remove(id)
                } else {
                    state.selectedIDs.insert(id)
                }
                return .none

            case .selectAllTapped:
                state.selectedIDs = state.isAllSelected ? [] : Set(state.displayedItems.map(\.id))
                return .none

            case let .selectionSwept(ids):
                guard state.isSelecting else { return .none }
                state.selectedIDs = ids.intersection(state.items.ids)
                return .none

            case let .sortOptionChanged(option):
                state.sortOption = option
                return .none

            case let .sortDirectionChanged(direction):
                state.sortDirection = direction
                return .none

            case let .restoreTapped(items):
                let available = items.filter(\.isAvailable)
                guard !available.isEmpty else { return .none }
                return .send(.restore(.restore(.items(available.map(\.id)), shareCount: available.shareCount)))

            case let .restoreToTapped(items):
                let available = items.filter(\.isAvailable)
                guard !available.isEmpty else { return .none }
                return .send(.restore(.restoreTo(.items(available.map(\.id)), shareCount: available.shareCount)))

            case let .deletePermanentlyTapped(items):
                guard !items.isEmpty, state.confirmPhase == .idle else { return .none }
                state.confirmation = .purge(ids: items.map(\.id), forget: false)
                state.confirmPhase.ask()
                return .none

            case let .forgetTapped(item):
                guard state.confirmPhase == .idle else { return .none }
                state.confirmation = .purge(ids: [item.id], forget: true)
                state.confirmPhase.ask()
                return .none

            case .emptyTrashTapped:
                guard !state.items.isEmpty, state.confirmPhase == .idle else { return .none }
                state.confirmation = .empty
                state.confirmPhase.ask()
                return .none

            case .confirmationDismissed:
                state.confirmPhase.cancel()
                if state.confirmPhase == .idle {
                    state.confirmation = nil
                }
                return .none

            case .confirmationConfirmed:
                guard state.confirmPhase.isConfirming, let confirmation = state.confirmation else { return .none }
                state.confirmPhase = .running
                let serverURL = state.serverURL
                let filesClient = filesClient
                switch confirmation {
                case let .purge(ids, forget):
                    return .run { send in
                        try await send(.purgeResponse(apiResult { try await filesClient.purgeTrash(
                            serverURL,
                            ids,
                            forget
                        ) }))
                    }
                    .cancellable(id: CancelID.mutation, cancelInFlight: true)
                case .empty:
                    return .run { send in
                        try await send(.emptyResponse(apiResult { try await filesClient.emptyTrash(serverURL) }))
                    }
                    .cancellable(id: CancelID.mutation, cancelInFlight: true)
                }

            case let .purgeResponse(result):
                state.confirmPhase = .idle
                state.confirmation = nil
                state.isSelecting = false
                state.selectedIDs = []
                state.notice = Self.notice(after: result, previous: state.notice)
                return load(&state)

            case let .emptyResponse(result):
                state.confirmPhase = .idle
                state.confirmation = nil
                state.isSelecting = false
                state.selectedIDs = []
                state.notice = Self.notice(after: result, previous: state.notice)
                return load(&state)

            case let .openLocationTapped(item):
                guard let path = item.openPath, let last = path.split(separator: "/").last else { return .none }
                let title = PersonalSpace.displayName(forSegment: String(last), isFirstSegment: !path.contains("/"))
                return .send(.delegate(.openPath(path: path, title: title)))

            case .restore, .folder, .delegate:
                return .none
            }
        }
        .ifLet(\.$folder, action: \.folder) {
            TrashFolderFeature()
        }
    }

    private func load(_ state: inout State) -> Effect<Action> {
        if !state.phase.hasLoaded || state.phase.errorMessage != nil {
            state.phase = .loading
        }
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            try await send(.loadResponse(apiResult { try await filesClient.fetchTrash(serverURL) }))
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    static func notice(
        after result: Result<TrashActionResult, FilesClientError>,
        previous: TrashNotice?
    ) -> TrashNotice {
        switch result {
        case let .success(result):
            var lines: [String] = []
            if !result.succeeded.isEmpty {
                lines.append(L10n.Trash.deletedPermanently(result.succeeded.count))
            }
            if let failure = result.failed.first {
                lines.append(L10n.Trash.notDeleted(result.failed.count) + " " + failure.status.reason)
            }
            return .after(previous, text: lines.joined(separator: "\n"), isFailure: result.succeeded.isEmpty)
        case let .failure(error):
            return .after(previous, text: error.userMessage, isFailure: true)
        }
    }

    static func notice(
        after result: Result<TrashEmptySummary, FilesClientError>,
        previous: TrashNotice?
    ) -> TrashNotice {
        switch result {
        case let .success(summary):
            var lines = [L10n.Trash.emptied(summary.purged)]
            if summary.leftBehind > 0 {
                lines.append(L10n.Trash.leftBehind(summary.leftBehind))
            }
            return .after(
                previous,
                text: lines.joined(separator: "\n"),
                isFailure: summary.leftBehind > 0 && summary.purged == 0
            )
        case let .failure(error):
            return .after(previous, text: error.userMessage, isFailure: true)
        }
    }
}

extension [TrashItem] {
    var shareCount: Int {
        reduce(0) { $0 + $1.shareCount }
    }
}
