import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation

/// An admin choosing how far folder sizes are counted (`off`, `shallow`, `full`) and which
/// folders to skip, via `PATCH /api/settings`. Mirrors the web client's `SettingsFolderSize.vue`.
/// The mode saves as soon as it changes; the excluded folders save with the Save button. When the
/// server's `FOLDER_SIZE_MODE` variable decided the mode, it is shown and cannot be changed.
@Reducer
public struct FolderSizeSettingsFeature {
    @ObservableState
    public struct State: Equatable, ExcludedPathsForm {
        public let serverURL: URL
        public var loaded: FolderSizeSettings?
        public var draftPaths: [String] = []
        public var newPath = ""
        public var lockedBy: String?
        public var phase: DataPhase = .idle
        public var isSaving = false
        public var errorMessage: String?
        public var isUnavailable = false

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        var loadedExcluded: ExcludedPaths? {
            loaded?.excluded
        }

        /// What the server is doing now. An environment variable can decide this, in which case
        /// the stored choice in the settings is not what runs.
        public var effectiveMode: FolderSizeMode?

        var mode: FolderSizeMode {
            effectiveMode ?? loaded?.mode ?? .off
        }

        var isModeLocked: Bool {
            lockedBy != nil || isSaving
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case loadResponse(Result<ServerSettingsSnapshot, FilesClientError>)
        case modeChanged(FolderSizeMode)
        case newPathChanged(String)
        case addPathTapped
        case pathToggled(String)
        case discardTapped
        case saveTapped
        case saveResponse(Result<FolderSizeSettings, FilesClientError>, replacesPaths: Bool)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case saved
        }
    }

    @Dependency(\.filesClient) var filesClient

    private enum CancelID { case load, save }

    public init() {}

    private func save(
        _ state: inout State,
        patch: SystemSettingsPatch.FolderSizePatch,
        replacesPaths: Bool
    ) -> Effect<Action> {
        state.isSaving = true
        state.errorMessage = nil
        return .saveSettings(
            filesClient,
            serverURL: state.serverURL,
            patch: SystemSettingsPatch(folderSize: patch),
            section: \.folderSize,
            missingMessage: "Settings response carried no folder size.",
            cancelLoad: CancelID.load,
            cancelID: CancelID.save,
            response: { .saveResponse($0, replacesPaths: replacesPaths) }
        )
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard !state.isSaving else { return .none }
                state.phase.beginReload()
                state.errorMessage = nil
                return .loadSnapshot(
                    filesClient,
                    serverURL: state.serverURL,
                    cancelID: CancelID.load,
                    response: { .loadResponse($0) }
                )

            case .loadResponse(.success) where state.isSaving:
                return .none

            case let .loadResponse(.success(snapshot)):
                state.phase = .loaded
                state.isUnavailable = false
                if let features = snapshot.features {
                    state.lockedBy = features.folderSizeLockedBy
                    state.effectiveMode = features.folderSizeMode
                }
                guard let settings = snapshot.settings.folderSize else {
                    state.isUnavailable = true
                    return .none
                }
                let keepsEdits = state.isDirty
                state.loaded = settings
                state.adopt(serverPaths: settings.excluded.paths, keepingUnsavedEdits: keepsEdits)
                return .none

            case let .loadResponse(.failure(error)):
                if state.loaded == nil {
                    state.phase = .failed(error.userMessage)
                } else {
                    state.errorMessage = error.userMessage
                }
                return .none

            case let .modeChanged(mode):
                guard state.lockedBy == nil, !state.isSaving, mode != state.mode else { return .none }
                return save(&state, patch: .init(mode: mode), replacesPaths: false)

            case let .newPathChanged(path):
                state.newPath = path
                return .none

            case .addPathTapped:
                state.addNewPath()
                return .none

            case let .pathToggled(path):
                state.togglePath(path)
                return .none

            case .discardTapped:
                state.discardPaths()
                return .none

            case .saveTapped:
                guard state.isSaveEnabled else { return .none }
                return save(&state, patch: .init(excludedPaths: state.draftPaths), replacesPaths: true)

            case let .saveResponse(.success(settings), replacesPaths):
                state.isSaving = false
                let keepsEdits = state.keepsUnsavedEdits(whenReplacing: replacesPaths)
                state.loaded = settings
                if !replacesPaths {
                    state.effectiveMode = settings.mode
                }
                state.adopt(serverPaths: settings.excluded.paths, keepingUnsavedEdits: keepsEdits)
                return .send(.delegate(.saved))

            case let .saveResponse(.failure(error), _):
                state.isSaving = false
                state.errorMessage = error.userMessage
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
