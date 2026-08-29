import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization

/// An admin editing the server's branding — app name and logo — via `PATCH /api/settings`
/// (and `POST /api/settings/upload-logo` for a new image). Mirrors the web client's
/// `SettingsBranding.vue`. Reached from the server row in Settings; non-admins never get here.
///
/// The server URL itself is fixed (it's the authenticated session's) and shown read only.
@Reducer
public struct ServerDetailsFeature {
    /// The largest an app name the server will store (`sanitizeBranding` truncates at 100).
    static let maxNameLength = 100
    /// The server rejects a logo over 2 MB; the client enforces the same before uploading.
    static let maxLogoBytes = 2 * 1024 * 1024

    /// Semantic name-field error; the view maps it to `L10n`.
    public enum NameError: Equatable, Sendable {
        case empty
    }

    @ObservableState
    public struct State: Equatable {
        public let serverURL: URL
        /// Branding as last known from the server — the baseline the form edits against.
        public var branding: Branding
        public var nameDraft: String
        /// A picked-but-unsaved logo, already downscaled and JPEG encoded by the view.
        public var pendingLogoData: Data?
        public var isSaving = false
        public var errorMessage: String?
        @Shared(.inMemory(Branding.sharedKey)) public var sharedBranding = Branding()

        public init(serverURL: URL, branding: Branding) {
            self.serverURL = serverURL
            self.branding = branding
            self.nameDraft = branding.appName
        }

        var trimmedName: String { nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) }

        var isNameValid: Bool {
            !trimmedName.isEmpty && trimmedName.count <= ServerDetailsFeature.maxNameLength
        }

        /// Shown under the field once it's been cleared — the draft starts as the current
        /// name, so an empty value is always a deliberate edit, not "not filled in yet".
        var nameError: NameError? {
            trimmedName.isEmpty ? .empty : nil
        }

        var isDirty: Bool {
            pendingLogoData != nil || trimmedName != branding.appName
        }

        var isSaveEnabled: Bool { isDirty && isNameValid && !isSaving }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case brandingResponse(Result<Branding, FilesClientError>)
        case nameChanged(String)
        case logoPicked(Data)
        case logoPickFailed
        case updateTapped
        case saveResponse(Result<Branding, FilesClientError>)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case brandingUpdated(Branding)
        }
    }

    @Dependency(\.filesClient) var filesClient

    private enum CancelID { case load, save }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    await send(.brandingResponse(await apiResult { try await filesClient.fetchBranding(serverURL) }))
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .brandingResponse(.success(branding)):
                let nameWasUntouched = state.nameDraft == state.branding.appName
                state.branding = branding
                state.$sharedBranding.withLock { $0 = branding }
                if nameWasUntouched { state.nameDraft = branding.appName }
                return .none

            case .brandingResponse(.failure):
                // Best effort: the caller already passed in the shared branding, so a failed
                // refresh just means the form edits against a possibly stale baseline.
                return .none

            case let .nameChanged(value):
                state.nameDraft = String(value.prefix(ServerDetailsFeature.maxNameLength))
                state.errorMessage = nil
                return .none

            case let .logoPicked(data):
                state.pendingLogoData = data
                state.errorMessage = nil
                return .none

            case .logoPickFailed:
                state.errorMessage = L10n.ServerDetails.logoErrorTooLarge
                return .none

            case .updateTapped:
                guard state.isSaveEnabled else { return .none }
                state.isSaving = true
                state.errorMessage = nil
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                let name = state.trimmedName
                let pendingLogo = state.pendingLogoData
                let currentLogoPath = state.branding.appLogoUrl
                return .run { send in
                    await send(.saveResponse(await apiResult {
                        let logoPath: String
                        if let pendingLogo {
                            logoPath = try await filesClient.uploadServerLogo(serverURL, pendingLogo)
                        } else {
                            logoPath = currentLogoPath
                        }
                        return try await filesClient.updateBranding(serverURL, name, logoPath)
                    }))
                }
                .cancellable(id: CancelID.save, cancelInFlight: true)

            case let .saveResponse(.success(branding)):
                state.isSaving = false
                state.branding = branding
                state.nameDraft = branding.appName
                state.pendingLogoData = nil
                state.$sharedBranding.withLock { $0 = branding }
                return .send(.delegate(.brandingUpdated(branding)))

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
