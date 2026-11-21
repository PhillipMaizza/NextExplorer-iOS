import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation

/// A section of `PATCH /api/settings` an admin edits as one choice that saves as soon as it
/// changes, plus the folders it leaves alone, saved with the Save button. The server's
/// environment can decide the choice, which is then shown and cannot be changed.
public protocol ExcludedPathsSection: SendableMetatype {
    associatedtype Settings: Equatable, Sendable
    associatedtype Choice: Equatable, Sendable

    /// What runs when nothing is loaded yet.
    static var defaultChoice: Choice { get }
    /// The decoding error when a saved settings echo lacks this section.
    static var missingMessage: String { get }
    static func section(of settings: SystemSettings) -> Settings?
    static func choice(of settings: Settings) -> Choice
    static func excluded(of settings: Settings) -> ExcludedPaths
    /// The environment variable that decided the choice, if one did.
    static func lockedBy(_ features: ServerFeatures) -> String?
    /// What the server runs now, whatever the settings store.
    static func effectiveChoice(_ features: ServerFeatures) -> Choice
    static func patch(choice: Choice) -> SystemSettingsPatch
    static func patch(excludedPaths: [String]) -> SystemSettingsPatch
}

/// The admin screen for one `ExcludedPathsSection`: folder sizes and the search index.
@Reducer
public struct ExcludedPathsSettingsFeature<Section: ExcludedPathsSection> {
    @ObservableState
    public struct State: Equatable, ExcludedPathsForm {
        public let serverURL: URL
        public var loaded: Section.Settings?
        public var draftPaths: [String] = []
        public var newPath = ""
        public var lockedBy: String?
        public var phase: DataPhase = .idle
        public var isSaving = false
        public var errorMessage: String?
        public var isUnavailable = false
        /// What the server is doing now. An environment variable can decide this, in which case
        /// the stored choice in the settings is not what runs.
        public var effectiveChoice: Section.Choice?

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        var loadedExcluded: ExcludedPaths? {
            loaded.map(Section.excluded(of:))
        }

        var choice: Section.Choice {
            effectiveChoice ?? loaded.map(Section.choice(of:)) ?? Section.defaultChoice
        }

        var isChoiceLocked: Bool {
            lockedBy != nil || isSaving
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case loadResponse(Result<ServerSettingsSnapshot, FilesClientError>)
        case choiceChanged(Section.Choice)
        case newPathChanged(String)
        case addPathTapped
        case pathToggled(String)
        case discardTapped
        case saveTapped
        case saveResponse(Result<Section.Settings, FilesClientError>, replacesPaths: Bool)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case saved
        }
    }

    @Dependency(\.filesClient) var filesClient

    private enum CancelID { case load, save }

    public init() {}

    private func save(_ state: inout State, patch: SystemSettingsPatch, replacesPaths: Bool) -> Effect<Action> {
        state.isSaving = true
        state.errorMessage = nil
        return .saveSettings(
            filesClient,
            serverURL: state.serverURL,
            patch: patch,
            section: { Section.section(of: $0) },
            missingMessage: Section.missingMessage,
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
                    state.lockedBy = Section.lockedBy(features)
                    state.effectiveChoice = Section.effectiveChoice(features)
                }
                guard let settings = Section.section(of: snapshot.settings) else {
                    state.isUnavailable = true
                    return .none
                }
                let keepsEdits = state.isDirty
                state.loaded = settings
                state.adopt(serverPaths: Section.excluded(of: settings).paths, keepingUnsavedEdits: keepsEdits)
                return .none

            case let .loadResponse(.failure(error)):
                if state.loaded == nil {
                    state.phase = .failed(error.userMessage)
                } else {
                    state.errorMessage = error.userMessage
                }
                return .none

            case let .choiceChanged(choice):
                guard state.lockedBy == nil, !state.isSaving, choice != state.choice else { return .none }
                return save(&state, patch: Section.patch(choice: choice), replacesPaths: false)

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
                return save(&state, patch: Section.patch(excludedPaths: state.draftPaths), replacesPaths: true)

            case let .saveResponse(.success(settings), replacesPaths):
                state.isSaving = false
                let keepsEdits = state.keepsUnsavedEdits(whenReplacing: replacesPaths)
                state.loaded = settings
                if !replacesPaths {
                    state.effectiveChoice = Section.choice(of: settings)
                }
                state.adopt(serverPaths: Section.excluded(of: settings).paths, keepingUnsavedEdits: keepsEdits)
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
