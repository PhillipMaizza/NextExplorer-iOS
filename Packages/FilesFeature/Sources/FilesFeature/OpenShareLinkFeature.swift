import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization

/// Drives the "Open a shared link" sheet (`OpenShareLinkSheet`). The user pastes a share
/// URL (or bare token) someone sent them; we look it up via `GET /api/share/<token>/info`
/// and, on confirm, hand the logical path `share/<token>` up to the Browse tab — a
/// signed-in user can browse an `anyone` share through the normal `/api/browse` endpoint
/// (`backend/src/services/accessManager.js` only denies when neither a user nor a guest
/// session is present).
@Reducer
public struct OpenShareLinkFeature {
    @ObservableState
    public struct State: Equatable {
        public let serverURL: URL
        public var linkText = ""
        public var isResolving = false
        public var info: ShareInfo?
        public var errorMessage: String?

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        var token: String? { OpenShareLinkFeature.token(from: linkText) }
        var canLookUp: Bool { token != nil && !isResolving }
        var canOpen: Bool {
            guard let info else { return false }
            return !info.isExpired
        }
    }

    public enum Action: Equatable, Sendable {
        case linkTextChanged(String)
        case lookUpTapped
        case infoResponse(Result<ShareInfo, FilesClientError>)
        case openTapped
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case open(path: String, title: String)
        }
    }

    @Dependency(\.filesClient) var filesClient

    private enum CancelID { case lookUp }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .linkTextChanged(text):
                state.linkText = text
                state.errorMessage = nil
                state.info = nil
                return .none

            case .lookUpTapped:
                guard let token = state.token else {
                    state.errorMessage = L10n.OpenShareLink.errorInvalidLink
                    return .none
                }
                state.isResolving = true
                state.errorMessage = nil
                state.info = nil
                let serverURL = state.serverURL
                let filesClient = self.filesClient
                return .run { send in
                    await send(.infoResponse(try await apiResult {
                        try await filesClient.resolveShareLink(serverURL, token)
                    }))
                }
                .cancellable(id: CancelID.lookUp, cancelInFlight: true)

            case let .infoResponse(.success(info)):
                state.isResolving = false
                if info.isExpired {
                    state.info = nil
                    state.errorMessage = L10n.OpenShareLink.errorExpired
                } else {
                    state.info = info
                }
                return .none

            case let .infoResponse(.failure(error)):
                state.isResolving = false
                state.errorMessage = Self.message(for: error)
                return .none

            case .openTapped:
                guard let info = state.info, !info.isExpired else { return .none }
                let title = info.label?.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = info.isDirectory
                    ? L10n.OpenShareLink.sharedFolder
                    : L10n.OpenShareLink.sharedFile
                return .send(.delegate(.open(
                    path: "share/\(info.shareToken)",
                    title: (title?.isEmpty == false ? title! : fallback)
                )))

            case .delegate:
                return .none
            }
        }
    }

    private static func message(for error: FilesClientError) -> String {
        switch error {
        case .server(statusCode: 404), .serverMessage(statusCode: 404, _):
            return L10n.OpenShareLink.errorNotFound
        default:
            return error.userMessage
        }
    }

    /// Pull a share token out of whatever the user pasted — a full share URL
    /// (`https://host/share/<token>?…`), a scheme-less one (`host/share/<token>`), or a
    /// bare token. Returns `nil` if nothing token-shaped is found.
    static func token(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: String
        if let range = trimmed.range(of: "/share/") {
            candidate = String(trimmed[range.upperBound...])
        } else {
            candidate = trimmed
        }

        // Drop any path/query/fragment tail.
        let tokenPart = candidate.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        let token = String(tokenPart)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard token.count >= 6, token.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return token
    }
}
