import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import FolderPickerFeature
import Foundation
import Localization

/// Inside a deleted folder: walk its subfolders, read a text file, and restore chosen entries (back
/// in their place inside the folder, or into a chosen folder) or the whole folder.
@Reducer
public struct TrashFolderFeature {
    @ObservableState
    public struct State: Equatable {
        public var serverURL: URL
        public var item: TrashItem
        /// Where inside the deleted folder the list is, "" for its top.
        public var path = ""
        public var phase: DataPhase = .idle
        public var entries: IdentifiedArrayOf<TrashEntry> = []
        public var isSelecting = false
        public var selectedNames: Set<TrashEntry.ID> = []
        public var restore: TrashRestoreFeature.State
        public var text: TrashTextPreview.State = .closed
        public var notice: TrashNotice?
        /// Restore Whole Folder is running: once it ends the folder is no longer in the trash.
        public var isRestoringWholeFolder = false

        public init(serverURL: URL, item: TrashItem) {
            self.serverURL = serverURL
            self.item = item
            restore = TrashRestoreFeature.State(serverURL: serverURL)
        }

        /// The title: the folder's name at its top, else the subfolder shown.
        public var title: String {
            path.split(separator: "/").last.map(String.init) ?? item.name
        }

        public var canGoUp: Bool {
            !path.isEmpty
        }

        var crumbs: [PathCrumb] {
            let parts = path.split(separator: "/").map(String.init)
            return [PathCrumb(title: item.name, path: "")] + parts.indices.map {
                PathCrumb(title: parts[$0], path: parts[...$0].joined(separator: "/"))
            }
        }

        public var selectedEntries: [TrashEntry] {
            entries.filter { selectedNames.contains($0.id) }
        }
    }

    public enum Action: Equatable, Sendable {
        case task
        case retryTapped
        case loadResponse(path: String, Result<TrashFolderListing, FilesClientError>)
        case entryTapped(TrashEntry)
        case upTapped
        case crumbTapped(path: String)
        case selectModeToggled
        case selectionToggled(TrashEntry.ID)
        case restoreTapped([TrashEntry])
        case restoreToTapped([TrashEntry])
        case restoreFolderTapped
        case textDismissed
        case textResponse(Result<TrashText, FilesClientError>)
        case restore(TrashRestoreFeature.Action)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            /// Entries left the trash, or the whole folder did and this screen closes.
            case restored(isWholeFolder: Bool)
        }
    }

    enum CancelID {
        case load, text
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

            case .retryTapped:
                return load(&state)

            case let .loadResponse(path, .success(listing)):
                guard path == state.path else { return .none }
                state.phase = .loaded
                state.item = listing.item
                state.entries = IdentifiedArray(listing.entries, uniquingIDsWith: { first, _ in first })
                return .none

            case let .loadResponse(path, .failure(error)):
                guard path == state.path else { return .none }
                state.phase = .failed(error == .offline ? error.userMessage : L10n.Trash.folderLoadFailed)
                return .none

            case let .entryTapped(entry):
                if state.isSelecting {
                    return .send(.selectionToggled(entry.id))
                }
                if entry.isDirectory {
                    state.path = entry.path(in: state.path)
                    return load(&state)
                }
                guard TrashTextPreview.canOpen(name: entry.name) else { return .none }
                return TrashTextPreview.open(
                    &state.text,
                    name: entry.name,
                    itemID: state.item.id,
                    path: entry.path(in: state.path),
                    serverURL: state.serverURL,
                    filesClient: filesClient
                )
                .map(Action.textResponse)
                .cancellable(id: CancelID.text, cancelInFlight: true)

            case .upTapped:
                guard state.canGoUp else { return .none }
                state.path = state.path.split(separator: "/").dropLast().joined(separator: "/")
                return load(&state)

            case let .crumbTapped(path):
                guard path != state.path else { return .none }
                state.path = path
                return load(&state)

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
                state.selectedNames = []
                return .none

            case let .selectionToggled(name):
                if state.selectedNames.contains(name) {
                    state.selectedNames.remove(name)
                } else {
                    state.selectedNames.insert(name)
                }
                return .none

            case let .restoreTapped(entries):
                guard let target = target(state, entries) else { return .none }
                return .send(.restore(.restore(target, shareCount: entries.reduce(0) { $0 + $1.shareCount })))

            case let .restoreToTapped(entries):
                guard let target = target(state, entries) else { return .none }
                return .send(.restore(.restoreTo(target, shareCount: entries.reduce(0) { $0 + $1.shareCount })))

            case .restoreFolderTapped:
                guard !state.restore.isRestoring else { return .none }
                state.isRestoringWholeFolder = true
                return .send(.restore(.restore(.items([state.item.id]), shareCount: state.item.shareCount)))

            case .restore(.delegate(.finished)):
                state.isSelecting = false
                state.selectedNames = []
                guard !state.isRestoringWholeFolder else {
                    state.isRestoringWholeFolder = false
                    return .send(.delegate(.restored(isWholeFolder: true)))
                }
                return .merge(load(&state), .send(.delegate(.restored(isWholeFolder: false))))

            case .restore, .delegate:
                return .none
            }
        }
    }

    /// The chosen entries by their path inside the deleted folder. One request never names an entry
    /// inside another, which the server refuses; entries listed side by side never are.
    private func target(_ state: State, _ entries: [TrashEntry]) -> TrashTarget? {
        guard !entries.isEmpty else { return nil }
        return .entries(itemID: state.item.id, paths: entries.map { $0.path(in: state.path) })
    }

    private func load(_ state: inout State) -> Effect<Action> {
        state.phase = .loading
        state.entries = []
        state.selectedNames = []
        let serverURL = state.serverURL
        let itemID = state.item.id
        let path = state.path
        let filesClient = filesClient
        return .run { send in
            try await send(.loadResponse(path: path, apiResult {
                try await filesClient.fetchTrashEntries(serverURL, itemID, path)
            }))
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }
}
