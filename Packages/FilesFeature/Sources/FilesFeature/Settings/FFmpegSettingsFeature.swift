import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation

/// An admin pointing the server at its `ffmpeg` and `ffprobe` binaries via `PATCH /api/settings`.
/// Mirrors the web client's `SettingsFfmpeg.vue`: a path must be absolute, and an empty field
/// clears the override so the server uses its default.
@Reducer
public struct FFmpegSettingsFeature {
    @ObservableState
    public struct State: Equatable {
        public let serverURL: URL
        public var loaded: FFmpegSettings?
        public var draft = FFmpegSettings()
        public var phase: DataPhase = .idle
        public var isSaving = false
        public var errorMessage: String?
        public var isUnavailable = false

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        /// The draft as it is sent. Spaces are trimmed here and not as the admin types, which
        /// would swallow a space in the middle of a path.
        var trimmedDraft: FFmpegSettings {
            FFmpegSettings(
                ffmpegPath: draft.ffmpegPath.trimmingCharacters(in: .whitespaces),
                ffprobePath: draft.ffprobePath.trimmingCharacters(in: .whitespaces)
            )
        }

        var isDirty: Bool {
            loaded != nil && trimmedDraft != loaded
        }

        /// The paths the admin changed, which is all that is sent.
        var patch: SystemSettingsPatch.FFmpegPatch {
            let trimmed = trimmedDraft
            return SystemSettingsPatch.FFmpegPatch(
                ffmpegPath: trimmed.ffmpegPath == loaded?.ffmpegPath ? nil : trimmed.ffmpegPath,
                ffprobePath: trimmed.ffprobePath == loaded?.ffprobePath ? nil : trimmed.ffprobePath
            )
        }

        var isValid: Bool {
            trimmedDraft.isValid
        }

        var isSaveEnabled: Bool {
            isDirty && isValid && !isSaving
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case loadResponse(Result<SystemSettings, FilesClientError>)
        case ffmpegPathChanged(String)
        case ffprobePathChanged(String)
        case saveTapped
        case saveResponse(Result<FFmpegSettings, FilesClientError>)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case saved
        }
    }

    @Dependency(\.filesClient) var filesClient

    private enum CancelID { case load, save }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard !state.isSaving else { return .none }
                state.phase.beginReload()
                state.errorMessage = nil
                return .loadSettings(
                    filesClient,
                    serverURL: state.serverURL,
                    cancelID: CancelID.load,
                    response: { .loadResponse($0) }
                )

            case .loadResponse(.success) where state.isSaving:
                return .none

            case let .loadResponse(.success(settings)):
                state.phase = .loaded
                state.isUnavailable = false
                guard let ffmpeg = settings.ffmpeg else {
                    state.isUnavailable = true
                    return .none
                }
                let untouched = !state.isDirty
                state.loaded = ffmpeg
                if untouched {
                    state.draft = ffmpeg
                }
                return .none

            case let .loadResponse(.failure(error)):
                if state.loaded == nil {
                    state.phase = .failed(error.userMessage)
                } else {
                    state.errorMessage = error.userMessage
                }
                return .none

            case let .ffmpegPathChanged(path):
                state.draft.ffmpegPath = path
                state.errorMessage = nil
                return .none

            case let .ffprobePathChanged(path):
                state.draft.ffprobePath = path
                state.errorMessage = nil
                return .none

            case .saveTapped:
                guard state.isSaveEnabled else { return .none }
                state.isSaving = true
                state.errorMessage = nil
                return .saveSettings(
                    filesClient,
                    serverURL: state.serverURL,
                    patch: SystemSettingsPatch(ffmpeg: state.patch),
                    section: \.ffmpeg,
                    missingMessage: "Settings response carried no ffmpeg.",
                    cancelLoad: CancelID.load,
                    cancelID: CancelID.save,
                    response: { .saveResponse($0) }
                )

            case let .saveResponse(.success(ffmpeg)):
                state.isSaving = false
                state.loaded = ffmpeg
                state.draft = ffmpeg
                return .send(.delegate(.saved))

            case let .saveResponse(.failure(error)):
                state.isSaving = false
                state.errorMessage = error.userMessage
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
