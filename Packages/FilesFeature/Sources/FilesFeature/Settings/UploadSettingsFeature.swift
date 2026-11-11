import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation

/// An admin editing how uploads are chunked via `PATCH /api/settings`. Mirrors the web client's
/// `SettingsUploads.vue`: forced chunking and the auto fallback exclude each other, and the chunk
/// size stays within the server's ceiling (`MAX_CHUNK_SIZE_MIB`, read from `/api/features`).
@Reducer
public struct UploadSettingsFeature {
    @ObservableState
    public struct State: Equatable {
        public let serverURL: URL
        public var loaded: UploadSettings?
        public var draft = UploadSettings()
        public var maxChunkSizeMiB = UploadSettings.fallbackMaxChunkSizeMiB
        public var phase: DataPhase = .idle
        public var isSaving = false
        public var errorMessage: String?
        public var isUnavailable = false

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        var chunkSizeMiB: Int {
            draft.chunkSizeMiB(maxMiB: maxChunkSizeMiB)
        }

        var isDirty: Bool {
            guard let loaded else { return false }
            return draft.isChunkedEnabled != loaded.isChunkedEnabled
                || draft.isChunkedAutoFallback != loaded.isChunkedAutoFallback
                || chunkSizeMiB != loaded.chunkSizeMiB(maxMiB: maxChunkSizeMiB)
        }

        var isSaveEnabled: Bool {
            isDirty && !isSaving
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case loadResponse(Result<ServerSettingsSnapshot, FilesClientError>)
        case chunkedChanged(Bool)
        case autoFallbackChanged(Bool)
        case chunkSizeChanged(Int)
        case saveTapped
        case saveResponse(Result<UploadSettings, FilesClientError>)
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
                return .loadSnapshot(filesClient, serverURL: state.serverURL, cancelID: CancelID.load, response: { .loadResponse($0) })

            case .loadResponse(.success) where state.isSaving:
                return .none

            case let .loadResponse(.success(snapshot)):
                state.phase = .loaded
                state.isUnavailable = false
                if let bytes = snapshot.features?.maxUploadChunkSizeBytes, bytes > 0 {
                    let mib = bytes / UploadSettings.bytesPerMiB
                    state.maxChunkSizeMiB = max(UploadSettings.minChunkSizeMiB, mib)
                }
                guard let uploads = snapshot.settings.uploads else {
                    state.isUnavailable = true
                    return .none
                }
                let untouched = !state.isDirty
                state.loaded = uploads
                if untouched {
                    state.draft = uploads
                }
                return .none

            case let .loadResponse(.failure(error)):
                if state.loaded == nil {
                    state.phase = .failed(error.userMessage)
                } else {
                    state.errorMessage = error.userMessage
                }
                return .none

            case let .chunkedChanged(isOn):
                state.draft.isChunkedEnabled = isOn
                if isOn {
                    state.draft.isChunkedAutoFallback = false
                }
                state.errorMessage = nil
                return .none

            case let .autoFallbackChanged(isOn):
                state.draft.isChunkedAutoFallback = isOn
                if isOn {
                    state.draft.isChunkedEnabled = false
                }
                state.errorMessage = nil
                return .none

            case let .chunkSizeChanged(mib):
                let clamped = min(max(mib, UploadSettings.minChunkSizeMiB), state.maxChunkSizeMiB)
                state.draft.chunkSizeBytes = clamped * UploadSettings.bytesPerMiB
                state.errorMessage = nil
                return .none

            case .saveTapped:
                guard state.isSaveEnabled else { return .none }
                state.isSaving = true
                state.errorMessage = nil
                var toSave = state.draft
                if let loaded = state.loaded, state.chunkSizeMiB == loaded.chunkSizeMiB(maxMiB: state.maxChunkSizeMiB) {
                    toSave.chunkSizeBytes = loaded.chunkSizeBytes
                } else {
                    toSave.chunkSizeBytes = state.chunkSizeMiB * UploadSettings.bytesPerMiB
                }
                return .saveSettings(
                    filesClient,
                    serverURL: state.serverURL,
                    patch: SystemSettingsPatch(uploads: toSave),
                    section: \.uploads,
                    missingMessage: "Settings response carried no uploads.",
                    cancelLoad: CancelID.load,
                    cancelID: CancelID.save,
                    response: { .saveResponse($0) }
                )

            case let .saveResponse(.success(uploads)):
                state.isSaving = false
                state.loaded = uploads
                state.draft = uploads
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
