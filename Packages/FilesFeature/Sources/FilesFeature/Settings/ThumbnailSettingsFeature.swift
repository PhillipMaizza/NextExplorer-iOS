import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

/// An admin editing the server's thumbnail generation config via `PATCH /api/settings`.
/// Mirrors the web client's `SettingsFilesThumbnails.vue`. These settings affect every
/// client that pulls from `GET /api/thumbnails/*`, this app included. Reached from the
/// Settings admin section; non-admins never get here (and the server would 403 the write).
@Reducer
public struct ThumbnailSettingsFeature {
    @ObservableState
    public struct State: Equatable {
        public let serverURL: URL
        /// Last known from the server; the baseline the form edits against. `nil` until the
        /// first load succeeds (or stays nil if the session isn't actually an admin).
        public var loaded: ThumbnailSettings?
        public var draft = ThumbnailSettings()
        public var phase: DataPhase = .idle
        public var isSaving = false
        /// Save failures only; a load failure lives in `phase`.
        public var errorMessage: String?
        /// Set when the load came back without a `thumbnails` object, i.e. not an admin.
        public var isUnavailable = false

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        var isDirty: Bool {
            loaded != nil && draft != loaded
        }

        var isSaveEnabled: Bool {
            isDirty && !isSaving
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case settingsResponse(Result<SystemSettings, FilesClientError>)
        case enabledChanged(Bool)
        case sizeChanged(Int)
        case qualityChanged(Int)
        case concurrencyChanged(Int)
        case saveTapped
        case saveResponse(Result<ThumbnailSettings, FilesClientError>)
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
                state.phase = .loading
                state.errorMessage = nil
                let serverURL = state.serverURL
                let filesClient = filesClient
                return .run { send in
                    try await send(.settingsResponse(apiResult {
                        try await filesClient.fetchSystemSettings(serverURL)
                    }))
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .settingsResponse(.success(settings)):
                state.phase = .loaded
                if let thumbnails = settings.thumbnails {
                    let untouched = !state.isDirty
                    state.loaded = thumbnails
                    if untouched {
                        state.draft = thumbnails
                    }
                } else {
                    state.isUnavailable = true
                }
                return .none

            case let .settingsResponse(.failure(error)):
                state.phase = .failed(error.userMessage)
                return .none

            case let .enabledChanged(value):
                state.draft.isEnabled = value
                state.errorMessage = nil
                return .none

            case let .sizeChanged(value):
                state.draft.size = value.clamped(to: ThumbnailSettings.sizeRange)
                state.errorMessage = nil
                return .none

            case let .qualityChanged(value):
                state.draft.quality = value.clamped(to: ThumbnailSettings.qualityRange)
                state.errorMessage = nil
                return .none

            case let .concurrencyChanged(value):
                state.draft.concurrency = value.clamped(to: ThumbnailSettings.concurrencyRange)
                state.errorMessage = nil
                return .none

            case .saveTapped:
                guard state.isSaveEnabled else { return .none }
                state.isSaving = true
                state.errorMessage = nil
                let serverURL = state.serverURL
                let draft = state.draft
                let filesClient = filesClient
                return .run { send in
                    try await send(.saveResponse(apiResult {
                        try await filesClient.updateThumbnailSettings(serverURL, draft)
                    }))
                }
                .cancellable(id: CancelID.save, cancelInFlight: true)

            case let .saveResponse(.success(thumbnails)):
                state.isSaving = false
                state.loaded = thumbnails
                state.draft = thumbnails
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

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
