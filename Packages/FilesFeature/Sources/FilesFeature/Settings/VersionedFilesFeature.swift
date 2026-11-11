import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation
import Localization

/// Every file that has a history, for an administrator: where the space of earlier versions has
/// gone, including the histories of files that no longer exist. Mirrors the web client's
/// `SettingsFileVersions.vue`: filter, page, open a history, tick versions, delete them.
@Reducer
public struct VersionedFilesFeature {
    /// What the admin asked to delete and has not yet confirmed.
    public enum Confirmation: Equatable, Sendable {
        case selected(fileID: String, versionIDs: [String])
        case all(fileID: String)

        var fileID: String {
            switch self {
            case let .selected(fileID, _), let .all(fileID): fileID
            }
        }
    }

    @ObservableState
    public struct State: Equatable {
        public let serverURL: URL
        public var filter = VersionedFilesFilter()
        public var page: VersionedFilesPage?
        public var offset = 0
        public var phase: DataPhase = .idle
        public var isReloading = false
        public var listError: String?

        public var expanded: Set<String> = []
        public var details: [String: VersionedFileDetail] = [:]
        public var detailErrors: [String: String] = [:]
        public var selection: [String: Set<String>] = [:]
        public var confirmation: Confirmation?
        public var isWorking = false

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        var files: [VersionedFile] {
            page?.files ?? []
        }

        func file(withID id: String) -> VersionedFile? {
            files.first { $0.id == id }
        }

        func chosen(_ fileID: String) -> Set<String> {
            selection[fileID] ?? []
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case pageResponse(Result<VersionedFilesPage, FilesClientError>)
        case queryChanged(String)
        case searchSubmitted
        case refreshTapped
        case zoneFilterChanged(String?)
        case stateFilterChanged(VersionedFileState?)
        case sortChanged(VersionedFileSort)
        case previousPageTapped
        case nextPageTapped
        case fileToggled(String)
        case detailResponse(fileID: String, Result<VersionedFileDetail, FilesClientError>)
        case versionToggled(fileID: String, versionID: String)
        case deleteSelectedTapped(fileID: String)
        case deleteAllTapped(fileID: String)
        case confirmationCancelled
        case confirmationConfirmed
        case deleteResponse(fileID: String, Result<VersionsDeletion, FilesClientError>)
    }

    @Dependency(\.filesClient) var filesClient

    private enum CancelID: Hashable { case page, detail(String), delete }

    public init() {}

    private func loadPage(_ state: inout State) -> Effect<Action> {
        if state.phase == .loaded {
            state.isReloading = true
        } else {
            state.phase = .loading
        }
        state.listError = nil
        let serverURL = state.serverURL
        let filter = state.filter
        let offset = state.offset
        let filesClient = filesClient
        return .api(
            cancelID: CancelID.page,
            operation: { try await filesClient.fetchVersionedFiles(serverURL, filter, offset, VersionedFilesPage.defaultPageSize) },
            response: { .pageResponse($0) }
        )
    }

    private func loadDetail(_ state: State, fileID: String) -> Effect<Action> {
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .api(
            cancelID: CancelID.detail(fileID),
            operation: { try await filesClient.fetchVersionedFile(serverURL, fileID) },
            response: { .detailResponse(fileID: fileID, $0) }
        )
    }

    /// A filter changed: back to the first page with every row closed, or the list shows page four
    /// of a different search.
    private func refilter(_ state: inout State) -> Effect<Action> {
        state.offset = 0
        state.expanded = []
        return loadPage(&state)
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.phase.shouldLoadOnAppear else { return .none }
                return loadPage(&state)

            case let .pageResponse(.success(page)):
                state.phase = .loaded
                state.isReloading = false
                state.page = page
                let shownIDs = Set(page.files.map(\.id))
                state.details = state.details.filter { shownIDs.contains($0.key) }
                state.selection = state.selection.filter { shownIDs.contains($0.key) }
                // A delete can leave the offset past the last row, which shows an empty page.
                if page.files.isEmpty, page.total > 0, state.offset > 0 {
                    let pageSize = VersionedFilesPage.defaultPageSize
                    state.offset = ((page.total - 1) / pageSize) * pageSize
                    return loadPage(&state)
                }
                return .none

            case let .pageResponse(.failure(error)):
                state.isReloading = false
                if state.phase.hasLoaded {
                    state.listError = error.userMessage
                } else {
                    state.phase = .failed(error.userMessage)
                }
                return .none

            case let .queryChanged(query):
                state.filter.query = query
                return .none

            case .searchSubmitted:
                return refilter(&state)

            case .refreshTapped:
                state.details = [:]
                let openRows = state.expanded.sorted()
                return .merge([loadPage(&state)] + openRows.map { loadDetail(state, fileID: $0) })

            case let .zoneFilterChanged(zoneID):
                state.filter.zoneID = zoneID
                return refilter(&state)

            case let .stateFilterChanged(fileState):
                state.filter.state = fileState
                return refilter(&state)

            case let .sortChanged(sort):
                state.filter.sort = sort
                return refilter(&state)

            case .previousPageTapped:
                guard let page = state.page, page.hasPrevious else { return .none }
                state.offset = max(0, state.offset - VersionedFilesPage.defaultPageSize)
                state.expanded = []
                return loadPage(&state)

            case .nextPageTapped:
                guard let page = state.page, page.hasNext else { return .none }
                state.offset += VersionedFilesPage.defaultPageSize
                state.expanded = []
                return loadPage(&state)

            case let .fileToggled(fileID):
                if state.expanded.contains(fileID) {
                    state.expanded.remove(fileID)
                    return .none
                }
                state.expanded.insert(fileID)
                guard state.details[fileID] == nil else { return .none }
                state.detailErrors[fileID] = nil
                return loadDetail(state, fileID: fileID)

            case let .detailResponse(fileID, .success(detail)):
                state.details[fileID] = detail
                state.detailErrors[fileID] = nil
                return .none

            case let .detailResponse(fileID, .failure(error)):
                state.detailErrors[fileID] = error.userMessage
                return .none

            case let .versionToggled(fileID, versionID):
                var chosen = state.chosen(fileID)
                if chosen.contains(versionID) {
                    chosen.remove(versionID)
                } else {
                    chosen.insert(versionID)
                }
                state.selection[fileID] = chosen.isEmpty ? nil : chosen
                return .none

            case let .deleteSelectedTapped(fileID):
                let ids = (state.details[fileID]?.versions ?? []).map(\.id).filter { state.chosen(fileID).contains($0) }
                guard !ids.isEmpty else { return .none }
                state.confirmation = .selected(fileID: fileID, versionIDs: ids)
                return .none

            case let .deleteAllTapped(fileID):
                state.confirmation = .all(fileID: fileID)
                return .none

            case .confirmationCancelled:
                state.confirmation = nil
                return .none

            case .confirmationConfirmed:
                guard let confirmation = state.confirmation else { return .none }
                state.confirmation = nil
                state.isWorking = true
                state.listError = nil
                let fileID = confirmation.fileID
                let ids: [String]? = switch confirmation {
                case let .selected(_, versionIDs): versionIDs
                case .all: nil
                }
                let serverURL = state.serverURL
                let filesClient = filesClient
                return .api(
                    cancelID: CancelID.delete,
                    operation: { try await filesClient.deleteVersionsOfFile(serverURL, fileID, ids) },
                    response: { .deleteResponse(fileID: fileID, $0) }
                )

            case let .deleteResponse(fileID, .success(outcome)):
                state.isWorking = false
                state.selection[fileID] = nil
                let effect: Effect<Action>
                if outcome.remaining > 0 {
                    // Both, in this order: the row's own counts come from the list and the versions
                    // under it from the history, and reloading one alone would show a row that says
                    // three versions above a list of none.
                    let reloadDetail = state.expanded.contains(fileID)
                    if !reloadDetail {
                        state.details[fileID] = nil
                    }
                    effect = .merge(
                        loadPage(&state),
                        reloadDetail ? loadDetail(state, fileID: fileID) : .none
                    )
                } else {
                    // A history with nothing left drops off the list, and may no longer exist to ask
                    // about, so it closes instead of being read again.
                    state.expanded.remove(fileID)
                    state.details[fileID] = nil
                    effect = loadPage(&state)
                }
                // After the reload starts, which clears the message line.
                if outcome.failed > 0 {
                    state.listError = L10n.VersionedFiles.deleteFailed
                }
                return effect

            case let .deleteResponse(_, .failure(error)):
                state.isWorking = false
                state.listError = error.userMessage
                return .none
            }
        }
    }
}
